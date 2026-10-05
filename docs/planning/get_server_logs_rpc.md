# Planning: `GetServerLogs` RPC via central Valkey

Status: **proposal.** Written 2026-10-05, updated 2026-10-05.

**Landed so far:** the `VIEW_SERVER_LOGS` permission (enum value, `set_permission` support,
`UpdateUser` protection with specs, Elm display name; see [the permission](#the-view_server_logs-permission))
and the [job log format](#preparatory-job-log-format) (timestamp, colored level and job name on the
periodic jobs' logs). Everything else here (the RPC, the `ServerLogSource` enum, the messages, the Valkey deployment, the
writer, the Elm tab) is **planned and not started**.

Lets a user holding `VIEW_SERVER_LOGS` view near-real-time logs from a Rellm namespace's `rellm`,
`rellm-jobs` and `rellm-preview-generator` workloads, through a new `GetServerLogs` RPC on the
`rellm` service. Logs flow through a **single, central Valkey** instance (next to central
Postgres/Silo in `rellm-storage`), not through the Kubernetes API.

> [!WARNING]
> **Read this before touching central Valkey: its users live in a Secret, not in Valkey.**
>
> Central Valkey has **no volume and no persistence**, by design (it costs no PVC; DOKS caps volumes
> at 15). That has one consequence that is easy to get wrong:
>
> - **Valkey's ACL users (`admin`, `probe`, and every namespace's `<ns>-writer` / `<ns>-reader`) are
>   NOT stored by Valkey.** The source of truth is the Secret **`rellm-central-valkey-acl` in
>   `rellm-storage`**. An `initContainer` rebuilds Valkey's ACL file from that Secret on **every pod
>   start**.
> - **Never create or change a user with only `ACL SETUSER`.** It works until the next Valkey
>   restart/reschedule, then that user silently disappears, every site's Valkey login starts failing,
>   and **logs just stop** (the apps keep running; the writers are fail-open). `ACL SAVE` does **not**
>   help: the ACL file lives on an `emptyDir` and is rebuilt from the Secret.
> - **Never delete, recreate, or `kubectl apply` a stale copy over that Secret.** It has one key per
>   namespace; change it only with per-key patches (the provisioning scripts do). Losing it means
>   every site loses realtime logs until each is re-provisioned.
> - A Valkey restart **does** wipe the buffered logs (expected: recent logs only) but **does not** lose
>   any users, as long as the Secret is intact.
> - The Secret holds password **hashes** only; plaintext passwords exist only in each namespace's own
>   `rellm-central-valkey` Secret. Include both in whatever backs up cluster Secrets.
> - The `default` ACL user must stay `off` (Valkey's default user is otherwise passwordless and fully
>   privileged over the network).
>
> This warning must be repeated everywhere Valkey is deployed or operated; see the
> [checklist](#where-this-warning-must-appear) below. It already appears in
> [`deploys/central_storage/README.md`](../../deploys/central_storage/README.md#central-valkey-planned).

## Contents

- [Decisions](#decisions)
- [Goals and non-goals](#goals-and-non-goals)
- [API](#api)
- [How it works](#how-it-works)
- [Protocol check: tonic, gRPC-Web, Elm](#protocol-check-tonic-grpc-web-elm)
- [Valkey deployment: central vs. per-namespace](#valkey-deployment-central-vs-per-namespace)
- [Central Valkey design](#central-valkey-design)
- [Configuration (env vars)](#configuration-env-vars)
- [NetworkPolicy support by provider](#networkpolicy-support-by-provider)
- [Lessons from the central-storage rollout](#lessons-from-the-central-storage-rollout)
- [Elm ServerLogsTab (final step)](#elm-serverlogstab-final-step)
- [Preparatory: job log format](#preparatory-job-log-format)
- [Implementation order](#implementation-order)
- [Rollout order](#rollout-order)
- [Risks](#risks)
- [Open questions](#open-questions)
- [Pre-existing issues found while researching](#pre-existing-issues-found-while-researching)

## Decisions

| Decision | Choice |
| --- | --- |
| Log store | **Valkey** (BSD-licensed Redis fork), Streams. Not Redis (license), not Kafka (weight), not Postgres/S3 (see [How it works](#how-it-works)). |
| Scope | **Near-real-time only.** Long-term retention is explicitly deferred. |
| Default caps | **1,000 INFO lines and 1,000 WARN+ lines, per source** (6 streams per namespace). Confirmed. |
| Transport | **Unary polling**, no server streaming for now. |
| Permission | `VIEW_SERVER_LOGS` (`10004`), not implied by `ADMIN`, not grantable via `UpdateUser`; only via the `set_permission` binary. Same treatment as `EDIT_CLUSTER_SETTINGS` / `EDIT_SERVER_MEDIA_ALLOCATION`. **Landed.** |
| Env var naming | `VALKEY_*`. |
| Topology | **Central Valkey only** for v1. See [below](#valkey-deployment-central-vs-per-namespace). |
| ACL persistence | **Secret-held ACL file** (one key per namespace, rebuilt into Valkey on every start). No PVC. **Confirmed**, and the top-of-doc warning exists because of it. |
| Request shape | `sources` plus a `cursor` and `limit` for polling (more than the original `sources = 1`). Confirmed. |
| Color | **Preserve ANSI color** end to end and render it in Elm (SGR allow-listed by the writer; level badge colored from the structured `level`). See [Color](#color). |
| UI | A **`ServerLogsTab`** right of the Cluster tab: a button with a dropdown of four checkboxes (All / Server / Job / Preview Generator Logs) above a scrollable log area. Built **last**. See [Elm ServerLogsTab](#elm-serverlogstab-final-step). |

## Goals and non-goals

Goals:

- See recent logs from all three workloads in the Elm SPA without `kubectl`, port-forwards or cluster
  credentials.
- Add no Kubernetes API credentials to the public-facing `rellm` pods (the main reason this isn't
  built on `kubectl logs` / the K8s API: it would put a cluster credential in the most exposed pod).
- Cost almost nothing on the cheapest hardware: one small pod for the whole cluster, **no PVC**.
- Be strictly optional and fail-open: no Valkey configured, or Valkey down, means the feature is
  off, never that the app is affected.

Non-goals (for now):

- History beyond the caps, search, or log shipping. (The path to retention later is a `rellm-jobs`
  consumer that drains the streams to object storage; see [Open questions](#open-questions).)
- Capturing output of processes that don't use the `log` crate (native libraries, Traefik, Stalwart).
  `kubectl logs` remains the source of truth for everything.
- Server streaming / true `tail -f`. Polling every 1-2 s is "reasonably accurate near-real-time".

## API

**Not in the protos yet.** This is the draft; when it lands, the long-form contract below moves into
doc comments in a new `protos/server_logs.proto` (house style: every message, field, enum value and
error documented there; `docs/Makefile`'s proto list needs the new file) and `rellm.proto` gets the
import and the `rpc`. Naming follows the repo's enum conventions (`..._UNKNOWN = 0`).

```proto
enum ServerLogSource {
  SERVER_LOG_SOURCE_UNKNOWN = 0;     // never valid in a request
  SERVER_LOG_SERVER = 1;             // deployment/rellm (2 replicas, interleaved)
  SERVER_LOG_JOBS = 2;               // deployment/rellm-jobs
  SERVER_LOG_PREVIEW_GENERATOR = 3;  // deployment/rellm-preview-generator
}

enum ServerLogLevel {
  SERVER_LOG_LEVEL_UNKNOWN = 0;
  SERVER_LOG_LEVEL_INFO = 1;         // INFO and anything more verbose
  SERVER_LOG_LEVEL_WARN = 2;
  SERVER_LOG_LEVEL_ERROR = 3;        // including panics
}

message GetServerLogsRequest {
  repeated ServerLogSource sources = 1;  // empty = all; duplicates ignored
  string cursor = 2;                     // opaque; empty = "newest `limit` lines"
  uint32 limit = 3;                      // 0 = default (200); server clamps to a max (1,000)
}

message GetServerLogsResponse {
  repeated ServerLogLine lines = 1;      // oldest first, interleaved across sources and replicas
  string next_cursor = 2;                // always set; equals the sent cursor if `lines` is empty
  bool gap = 3;                          // lines between `cursor` and the first returned line were trimmed
  bool has_more = 4;                     // more lines were already waiting; poll again immediately
}

message ServerLogLine {
  ServerLogSource source = 1;
  string pod = 2;                        // which replica
  ServerLogLevel level = 3;
  google.protobuf.Timestamp timestamp = 4;  // assigned by the log store (no pod clock skew)
  string text = 5;                       // the message; may contain ANSI SGR color sequences (see "Color")
}

// rpc GetServerLogs(GetServerLogsRequest) returns (GetServerLogsResponse) {}
```

The polling contract to document in the protos:

- First call: empty `cursor`, newest `limit` lines. Each response's `next_cursor` goes back as `cursor`
  on the next call. **Clients treat the cursor as opaque.**
- With an empty `cursor` the *newest* `limit` lines are returned; with a `cursor`, the *oldest* `limit`
  lines after it, so a client that fell behind catches up in order. `has_more` (not "got exactly
  `limit` lines", which the client can't know because the server clamps) says to poll again immediately.
- A `cursor` is only meaningful for the same set of `sources` it was returned for. Changing the set
  means starting over with an empty cursor.
- An **empty `sources` list means all sources, not none.** The proto docs should say so loudly, and
  clients with a "nothing selected" state (the `ServerLogsTab` has one) must not send a request at all.
- `gap = true` means lines were trimmed between polls (or the log store reset): the client should show
  a "some lines are missing" marker, not silently stitch ranges together. Always `false` for an empty
  `cursor`.
- Retention is "recent logs": ~1,000 INFO plus ~1,000 WARN/ERROR lines per source, nothing across a
  Valkey restart. `kubectl logs` remains the source of truth.

Errors the Elm UI must be able to distinguish:

| Condition | Code / message |
| --- | --- |
| Not logged in | `UNAUTHENTICATED` `authentication_required` (existing) |
| Missing permission | `INVALID_ARGUMENT` `permission_VIEW_SERVER_LOGS_required` (existing `validate_exact_permission` convention) |
| Unknown `sources` entry / malformed cursor | `INVALID_ARGUMENT` (`invalid_cursor` for the cursor) |
| Log storage not configured | `FAILED_PRECONDITION` `server_logs_not_configured` |
| Log storage configured but unreachable | `UNAVAILABLE` |
| Server predates the RPC | `UNIMPLEMENTED` |

### The `VIEW_SERVER_LOGS` permission

New enum value `10004`, documented in `protos/permissions.proto` like its siblings. When the RPC
lands it is checked with `validate_exact_permission` (exact match, so `ADMIN` doesn't imply it).
Hand-maintained places (the repo's known "silently dropped enum value" gotcha):

| Where | What | Status |
| --- | --- | --- |
| `protos/permissions.proto` | `VIEW_SERVER_LOGS = 10004` with docs | ✅ done |
| `backend/src/marshaling/permission_marshaling.rs` | `ALL_PERMISSIONS` (length bumped to 56); this is what makes `set_permission` accept it | ✅ done |
| `backend/src/rpcs/users/update_user.rs` | carried forward, never grantable/revocable via `UpdateUser` (the existing two special cases became one `NEVER_GRANTABLE_VIA_UPDATE_USER` list) | ✅ done |
| `backend/src/tests/update_user_view_server_logs_tests.rs` | grant/revoke specs (mirror `update_user_server_media_allocation_tests.rs`) | ✅ done, passing |
| `frontends/elm-spa/src/Components/Users.elm` | `permissionText` ("View Server Logs"). **Not** `allPermissions` (the "Add Permission" selector) and **not** `configurableServerPermissions` | ✅ done |
| `frontends/elm-spa/src/Shared/AccountsPanel/RellmAccounts.elm` | `permissionFromInt` maps `10004` (and now `10003`; see [Pre-existing issues](#pre-existing-issues-found-while-researching)) | ✅ done |
| Generated Elm / Flutter / Tamagui bindings | regenerated | ✅ done |
| `docs/protocol.md` / `protocol.html` | regenerated (only the new permission's rows changed) | ✅ done |
| `GetServerLogs` itself | `validate_exact_permission(..., ViewServerLogs)` plus a spec that `ADMIN` alone is rejected | ⏳ with the RPC |

## How it works

```text
 rellm (x2) ──┐
 rellm-jobs ──┼─ XADD (batched, async, fail-open) ─▶  central Valkey (rellm-storage)
 preview-gen ─┘   per-namespace "writer" ACL user       streams: logs:<ns>:<source>:{info,warn}
                                                        capped by MAXLEN, no persistence
 Elm ── GetServerLogs (unary, polled) ─▶ rellm ── XRANGE/XREVRANGE (per-namespace "reader" ACL user)
```

Why Valkey (vs. the alternatives we considered): near-real-time is the only requirement, and logs
there are a capped ring buffer. Valkey Streams give exactly that (`XADD ... MAXLEN`, ordered by
server-assigned IDs) with no flush interval (unlike S3, whose objects are immutable, so a crash
loses the unflushed buffer), no dependency on the app's own Postgres (the DB being down is exactly
when you need logs), and no Kubernetes credentials. Kafka is far heavier than this needs.

### Writers

- Hook the `log` crate: a custom `log::Log` that **tees** to the existing `env_logger` (stdout stays
  exactly as it is, so `kubectl logs` is unchanged and remains the source of truth) and also queues
  the record for Valkey. Both `main.rs` and `init_bin_logging` in `backend/src/lib.rs` initialize
  `env_logger` today and both need the hook.
- Capture the level from the `log::Record`, **not** from stdout: `env_logger` is configured with
  `format_level(false)`, `format_timestamp(None)` and no target, so stdout lines carry neither level
  nor time. (The stream ID supplies the time.)
- A bounded in-process channel and a background task that batches `XADD`s with a pipeline every
  ~100 ms. On overflow, drop newest and emit a periodic "N log lines dropped" line. Never block the
  caller, never panic.
- Fields per entry: `pod` (`HOSTNAME`), `level`, `text`. Truncate `text` to
  `VALKEY_LOG_MAX_LINE_BYTES` (default 2 KiB; `RUST_BACKTRACE=full` panics are huge). Strip control
  characters, but **keep ANSI SGR color sequences** (`ESC [ digits/semicolons m`, length-bounded) so
  the UI can render them; see [Color](#color). Truncation must not cut inside an escape sequence.
- Exclude the Valkey client's own crates (and its connection errors) from the Valkey sink, or a
  Valkey outage becomes a feedback loop.
- Redact at write time (database URLs, bearer tokens, `Authorization` headers, emails), since
  Valkey data is unencrypted in memory and in transit.
- Auth or connection failure: exponential backoff, and at most one warning per minute to stdout.
- Install a panic hook that logs through the same path, so panic text reaches Valkey before the
  process dies. (An OOM-kill loses only what's still in the in-process channel: milliseconds.)
- **Startup must not fail if Valkey is unreachable.** Contrast with the backend's object storage
  check, which `expect`s at boot. Valkey is optional and best-effort.

### Streams, caps and ordering

- Keys: `logs:<namespace>:<source>:<level-bucket>`, with source in `server|jobs|preview-generator`
  and bucket in `info|warn`. A line goes to exactly one bucket by its level (INFO and below to
  `info`; WARN/ERROR to `warn`). This is why a WARN+ stream exists separately: an INFO storm can't
  push the one interesting error out of the buffer.
- Defaults: `VALKEY_LOG_INFO_MAX_LINES=1000`, `VALKEY_LOG_WARN_MAX_LINES=1000`, **per source**, via
  `XADD ... MAXLEN = <n>` (exact trimming; the cost is negligible at this size, and `~` can overshoot
  by a stream node).
- Both `rellm` replicas write the same streams. Entry IDs are assigned by Valkey, so interleaving
  across replicas is ordered with no clock-skew problem (each line carries its `pod`).
- Memory per namespace is bounded by `6 streams x 1000 lines x line size`. At the 2 KiB line cap
  that is at most ~12 MiB per namespace and, typically, a couple of MiB. Estimates only; measure
  once real logs flow. Sizing for the central instance follows from this (see
  [Central Valkey design](#central-valkey-design)).

### Reading and the polling cursor

- First call (empty cursor): `XREVRANGE` the newest `limit` entries from each requested
  source's two streams, merge by ID, return oldest-first.
- Subsequent calls: send back `next_cursor` (a Valkey stream ID); the server `XRANGE`s from
  *exclusive* `(cursor`, merges, caps at `limit`, and sets `has_more` if it stopped early.
- IDs are time-based on the one Valkey server, so IDs from different streams are comparable and a
  single cursor works for all of them.
- **Read all of a poll's streams in one `MULTI`/`EXEC`.** Reading stream A, then stream B a few ms
  later, and taking the highest ID as the next cursor would permanently skip entries that landed in
  A between the two reads. This is the easiest bug to ship here.
- If the cursor is older than the oldest retained entry, set `gap = true`.
- Authorization is checked before any Valkey call; `sources` is validated against the enum.
  Per-call caps on `limit` and on response bytes.

## Protocol check: tonic, gRPC-Web, Elm

Requested as a precondition for polling. Result: **no blockers; two things to confirm at runtime.**

- **tonic / gRPC-Web:** `backend/src/servers/tonic.rs` serves with `accept_http1(true)` plus
  `GrpcWebLayer` (and a permissive `CorsLayer`). A unary `GetServerLogs` is served exactly like every
  other RPC, so polling needs nothing new on the server. (Server streaming over gRPC-Web is
  supported by `tonic-web`, but it's out of scope; the unary design avoids it entirely.)
- **Elm bindings (`protoc-gen-elm`):** the new messages need a `repeated` enum in the request
  (`sources`). The generated bindings already do this elsewhere: `GetEventsRequest.rsvp_statuses`
  generates `rsvpStatuses : List RsvpStatus` encoded with `Protobuf.Encode.list`, and enums carry a
  `...Unrecognized_` fallback. `google.protobuf.Timestamp` is already used throughout.
- **To confirm when implementing (first smoke test):** no Elm page currently *sends* a repeated-enum
  field (a grep found none), so verify that the request body round-trips. `Encode.list` emits the
  field as repeated entries rather than packed. The protobuf spec requires decoders to accept both,
  and prost does, but confirm with the local backend before building UI on it. If it somehow fails,
  the fallback is declaring `sources` as `repeated int32`, which isn't worth doing unless the smoke
  test fails.
- Polling cost: one small unary request every ~2 s per open `ServerLogsTab`, each doing one `MULTI`/`EXEC`.
  Cap concurrent pollers per user if this ever matters.

## Valkey deployment: central vs. per-namespace

The goal is to host many namespaces on the cheapest possible hardware, so the question is what each
option adds per namespace.

| | Central (one instance in `rellm-storage`) | Per-namespace (a pod in each site's namespace) |
| --- | --- | --- |
| Pods | 1 for the whole cluster | +1 per site. On 1-2 vCPU nodes, pod count and resource *requests* are what bind first. |
| PVCs | 0 (no persistence) | 0 |
| Provisioning | one script slice per namespace (ACL users + Secret), the same shape as `provision_namespace.sh` | a manifest, a Secret and a rollout per namespace |
| Isolation | ACL users scoped to `~logs:<ns>:*`; **a mistake leaks one site's logs to another** | strong by construction |
| Failure blast radius | Valkey down/full means no realtime logs for **every** site (apps unaffected; fail-open) | one site |
| Shared memory limit | a log storm in one site eats the shared `maxmemory` (bounded by the caps) | isolated |
| NetworkPolicy | one policy to write, but cross-namespace ingress rules needed | simpler, same-namespace only |
| Matches existing pattern | yes: exactly how Postgres and Silo work (shared instance, per-namespace credentials, `${STORAGE_NAMESPACE}` DNS) | no |

**Decision: central only for v1.** Every cost that matters here scales with namespace count under the
per-namespace option and not under the central one, and the data is small, ephemeral and
non-critical. The central option's real cost is the isolation risk and the shared blast radius;
both are mitigated below (ACL scoping with a proving probe at provision time, caps that bound memory,
fail-open writers).

"No central storage, no realtime logs" is nearly true but doesn't need to be. Because the backend
only knows `VALKEY_URL`/`VALKEY_READ_URL`, topology is purely a deploy-side matter:

- Central Valkey is created by `create_central_storage` along with Postgres and Silo.
- A namespace's Valkey slice is provisioned by its own script/target (see
  [Central Valkey design](#central-valkey-design)), so existing central-storage namespaces can be
  **backfilled** and legacy per-namespace-storage namespaces can opt in, because cross-namespace
  service DNS already works for Postgres/Silo and works the same for Valkey.
- "Bring your own Valkey" (a per-namespace pod, managed Valkey, anything): create a
  `rellm-central-valkey`-shaped Secret by hand with your URLs. We don't ship a per-namespace manifest;
  if someone really wants one it's a follow-up that needs nothing from the backend.

## Central Valkey design

Mirrors `deploys/central_storage/` (see its README). Everything below is a proposal.

### The instance

- `deploys/central_storage/k8s/k8s-central-valkey-<provider>.yaml` (name follows the existing
  per-provider convention even though nothing in it is provider-specific): a `Service` plus a
  `Deployment` (replicas 1, `Recreate`). A Deployment rather than a StatefulSet because there is no
  volume and no stable identity.
- **No PVC**: `--save "" --appendonly no`. This is the point of the design; the PVC budget (DOKS caps
  attached volumes at 15, and central storage uses 2 for exactly that reason) is untouched.
- `--maxmemory` ~ 256 MiB to start, `--maxmemory-policy noeviction`, container memory limit with
  headroom above `maxmemory` for fragmentation and client buffers.
  **Never `allkeys-*` eviction**: a stream is one key, so eviction would delete a site's entire log.
  With `noeviction`, a full instance makes `XADD` fail for everyone, which the writers treat as
  "drop". Size from the per-namespace bound above; at ~2 MiB typical per namespace, 256 MiB covers
  on the order of 100 sites, and the worst case (every line at the cap) is much higher, so
  alert on memory (`make get_central_valkey_memory`, `INFO memory`).
- Pin an exact image tag (`valkey/valkey:<x.y.z>`), like Silo's pinned `RELEASE...` tag. Valkey, not
  Redis: Redis 8 is AGPL and 7.4+ moved off BSD.
- Unlike the existing manifests, set resource requests/limits on this one; memory is the specific
  failure mode.

### Credentials and ACLs

> [!WARNING]
> **Everything in this section is the "users live in a Secret" design from the
> [warning at the top](#planning-getserverlogs-rpc-via-central-valkey).** Valkey is rebuilt from the
> Secret on every start; anything you do to a user directly in Valkey is temporary.

- **Valkey's `default` user is passwordless and fully privileged unless disabled.** The ACL file must
  contain `user default off`. This is the Valkey equivalent of Postgres's `trust` socket
  connections, except it applies to the network.
- Users (all defined in an ACL file; passwords stored as SHA-256 hashes):
  - `admin`: full access, only used by provisioning scripts. Password lives in
    `rellm-central-valkey-credentials` in `rellm-storage`, generated once and never regenerated if it
    exists (same as the Postgres/Silo admin Secrets).
  - `probe`: `+ping` only, for the readiness/liveness `exec` probe.
  - per namespace `<ns>-writer`: `~logs:<ns>:*`, `-@all +xadd +ping +hello` (and whatever the client
    handshake needs, e.g. `+client|setinfo`; confirm).
  - per namespace `<ns>-reader`: `~logs:<ns>:*`, `-@all +xrange +xrevrange +xlen +multi +exec +ping +hello`.
- The writer/reader split means a compromised `rellm-jobs` or preview-generator pod can forge log
  lines for its own namespace but can't read any. Only `rellm` holds reader credentials.
- Namespace names are DNS-1123 labels (no `*`, `?`, `[`, `]`, `\`, `:`), so embedding them in a key
  glob is safe. This is the same validation `provision_namespace.sh` already enforces; keep it.
- **ACL persistence without a volume (decided: Secret-held ACL file).** Users created only via
  `ACL SETUSER` vanish when the pod restarts, breaking every site's Valkey login until re-provisioned.
  Postgres doesn't have this problem because roles live on its PVC. The design:
  - A Secret `rellm-central-valkey-acl` in `rellm-storage` with **one key per namespace**
    (`<ns>.acl`, holding that namespace's two hashed-password user lines) plus a `base.acl`
    (`default off`, `admin`, `probe`).
  - Provisioning sets a namespace's key with `kubectl patch secret --type merge`. That is atomic
    per key, so concurrent provisions of different namespaces can't clobber each other. This is the
    class of race fixed in the central-storage work with advisory locks and kernel-chosen
    port-forward ports.
  - An `initContainer` concatenates `*.acl` into the emptyDir file Valkey runs with
    (`--aclfile`). Pod restarts therefore rebuild all users. (`ACL SAVE` would write to that
    emptyDir and be lost; it is not a persistence mechanism here.)
  - Provisioning *also* runs `ACL SETUSER` live via `kubectl exec` (using `REDISCLI_AUTH`, not a
    command-line password), so a new namespace works immediately instead of after the kubelet syncs
    the Secret volume. A `make verify_central_valkey_acl` target diffs `ACL LIST` against the Secret
    to catch drift (a user that exists live but not in the Secret is exactly the failure the warning
    describes).
  - The Secret holds hashes only; plaintext passwords exist only in each namespace's own Secret.
  - Rejected alternative: a 1 GiB PVC for `ACL SAVE`, which costs one of the 15 volumes.

### Where this warning must appear

When Valkey is implemented, repeat the warning (short form, linking here) in each of:

- [x] `deploys/central_storage/README.md`: the "Central Valkey (planned)" section (landed with this plan).
- [ ] `deploys/README.md`: the "One-time cluster setup" step for central storage, and its credentials section.
- [ ] The Valkey manifest's header comment (`k8s-central-valkey-*.yaml`).
- [ ] `provision_valkey_namespace.sh` and `deprovision_...` headers and `--help`.
- [ ] `deploys/central_storage/Makefile` comments for `create/update/restart/delete_central_valkey`, and the
  `restart_` and `delete_` targets should **print** a short reminder (restart wipes buffered logs, not
  users; deleting the ACL Secret loses every site's login).
- [ ] `deploys/Makefile`'s `get_all_storage_credentials` comment (and the new Secrets added to
  `storage_credential_secrets`).
- [ ] The failure message when Valkey auth fails during provisioning's probe step ("the user exists live
  but is not in the ACL Secret" is the first thing to check).
- [ ] `docs/architecture` notes next to the diagram update.

### Per-namespace provisioning and cleanup

New scripts, mirroring `provision_namespace.sh` / `deprovision_namespace.sh` (`set -Eeuo pipefail`,
`--check`, `--reset`, `on_error` that says what is half-done):

- `provision_valkey_namespace.sh <ns>` (and `make create_backend_central_valkey`): generates the two
  passwords, patches the ACL Secret key, applies `ACL SETUSER`, **verifies scoping before finishing**
  (the writer can `XADD` its own key; the writer is denied `XADD` to another namespace's key, `XRANGE`,
  `FLUSHALL` and `CONFIG`; the reader can `XRANGE` its key and is denied `XADD`; mirrors the Silo
  probe that creates a second bucket and expects denial), then writes the namespace Secret.
- `provision_namespace.sh` calls it as a final step **only if central Valkey exists**, printing a
  notice and continuing otherwise, so the feature stays optional and `create_backend_central_data`
  keeps working on clusters that haven't created Valkey.
- The namespace Secret `rellm-central-valkey` has `valkey-url` (writer), `valkey-read-url` (reader)
  and `valkey-key-prefix` (`logs:<ns>`). **A separate Secret from `rellm-central-data`**, so that
  backfilling an existing namespace doesn't have to patch a Secret that
  `provision_namespace.sh --reset` deletes and recreates.
- `deprovision_namespace.sh` (and `make delete_backend_central_data`) gets a matching step:
  `ACL DELUSER` both users, remove the ACL Secret key, `SCAN`+`DEL` `logs:<ns>:*`, delete the
  namespace Secret. Written **alongside** provisioning, not after (cleanup was added late in the
  central-storage work). Unlike the DB/bucket case, it needn't refuse while the site is running:
  writers are fail-open and just back off.
- Make targets in `deploys/Makefile` passthroughs (`create_central_valkey`, `update_`, `restart_`,
  `delete_`, `get_central_valkey_memory`, `verify_central_valkey_acl`), `create_central_storage` gains
  `create_central_valkey`.
- A one-time `backfill` loop over existing namespaces, like the transition tooling, plus the
  per-namespace manifest rollout described under [Rollout order](#rollout-order).

### Local dev and CI

- `backend/Makefile`: `local_valkey_start` next to `local_object_storage_start`, and an entry in
  `backend/.env-example`. If `VALKEY_URL` is unset locally, the feature is simply disabled.
- Tests: the Valkey sink and reader sit behind a small trait so most logic (batching, drop
  policy, cursor merge, redaction, truncation) is unit-testable without a server. Integration tests
  are gated on `TEST_VALKEY_URL`. CI's test job already starts Silo by hand and a `postgres:16`
  service; Valkey is a one-line addition there (`services:` with a `valkey-cli ping` health check),
  but keep it optional.
- The Homebrew/Linux distributable scripts (`docs/rellm_homebrew.sh`, `docs/rellm_linux.sh`) document
  env vars and bundle services; note `VALKEY_*` as optional. No Dockerfile change is expected.

## Configuration (env vars)

All optional. Nothing set means the feature is disabled and `GetServerLogs` returns the
"not configured" error.

| Variable | Default | Purpose |
| --- | --- | --- |
| `VALKEY_URL` | unset | Writer connection (`redis://` scheme; the Rust client is protocol-compatible). Set on `rellm`, `rellm-jobs`, `rellm-preview-generator`. |
| `VALKEY_READ_URL` | unset | Reader connection. Set on `rellm` **only**, so jobs/preview-generator pods can't read logs. |
| `VALKEY_KEY_PREFIX` | unset | `logs:<namespace>`. The app doesn't otherwise know its namespace, and the ACL key pattern must match it. |
| `VALKEY_LOG_INFO_MAX_LINES` | `1000` | `MAXLEN` for each source's `info` stream. |
| `VALKEY_LOG_WARN_MAX_LINES` | `1000` | `MAXLEN` for each source's `warn` stream. |
| `VALKEY_LOG_MAX_LINE_BYTES` | `2048` | Truncation of a single line. |

In manifests, source these from the `rellm-central-valkey` Secret with `secretKeyRef` and
`optional: true` (the precedent is `TLS_KEY`/`TLS_CERT` in `server_internal_central_data.yaml`), so
a rollout before the Secret exists is harmless. Add them to **all** server manifests (central-data,
plain per-namespace, insecure, external), not only the central-data ones, or non-central namespaces
silently lack the feature.

## NetworkPolicy support by provider

Why it matters: central storage's README already lists "no NetworkPolicy" as not covered. Today any
pod in the cluster can *attempt* to reach Postgres and Silo (it just can't authenticate). Valkey
makes the same gap more interesting: a mis-set ACL, or a pod that guesses nothing but reaches an
unauthenticated port, is a bigger deal than a failed login. A single NetworkPolicy in `rellm-storage`
(allow ingress to Postgres/Silo/Valkey only from namespaces that hold a `rellm-central-*` Secret
user) would cover all three, so this is worth doing for all three, not just Valkey.

Enforcement depends on the cluster's CNI, not on whether the `NetworkPolicy` object is accepted: an
unenforced policy applies without error and does nothing.

| Provider | Default CNI | Enforces `NetworkPolicy`? | Notes |
| --- | --- | --- | --- |
| **DigitalOcean (DOKS)** | Cilium (not changeable) | **Yes** | [DOKS Cilium network policies](https://www.digitalocean.com/community/tutorials/doks-cilium-network-policies-observability); [DOKS features](https://docs.digitalocean.com/products/kubernetes/details/features/). Confirm with the live test below before relying on it. |
| **AWS EKS** | Amazon VPC CNI | **Yes, but opt-in** | Native since VPC CNI v1.14.0, Kubernetes 1.25+, kernel 5.10+ EKS-optimized AMI; **disabled by default**, you must enable it on the add-on. [AWS announcement](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-vpc-cni-kubernetes-networkpolicy-enforcement/) |
| **Google GKE** | Dataplane V2 (Cilium-based) on Autopilot / new clusters | **Yes** | Always enforced with Dataplane V2 and in Autopilot (can't be disabled). Standard clusters without Dataplane V2 must opt in to network policy enforcement. [GKE docs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy) |
| **Azure AKS** | Azure CNI (policy engine is a choice) | **Yes, but opt-in at creation** | Engines: Azure Network Policy Manager, Calico, or Cilium (Azure CNI Powered by Cilium, recommended). **NPM is unsupported from 2028-09-30.** [AKS network policies](https://learn.microsoft.com/en-us/azure/aks/use-network-policies) |
| **Linode (LKE)** | Calico (standard); Cilium (LKE Enterprise) | **Yes** (per vendor docs / search results; verify) | [LKE overview](https://techdocs.akamai.com/cloud-computing/docs/linode-kubernetes-engine) |
| **Civo** | Flannel by default | **No by default**; yes if Calico or Cilium is chosen **at cluster creation** | Flannel does not enforce policies. [Civo CNI guide](https://www.civo.com/academy/kubernetes-networking/container-network-interfaces) |
| **OVHcloud** | Canal (Calico for policy + Flannel for networking) | **Yes** (per search results; verify) | |
| **Scaleway (Kapsule)** | Cilium or Calico (your choice) | **Yes** | Kapsule supports only these two. |

Provider coverage matches the set in [`docs/k8s_providers.md`](../k8s_providers.md). The table is a
starting point from public documentation; **verify on the cluster you actually run.** Quick live test:
in a scratch namespace apply a default-deny ingress policy to a pod running `valkey-cli ping` (or
any listener), then from a pod in another namespace try to connect. If the connection still succeeds,
the cluster is not enforcing policies, whatever the docs say. This is worth turning into a
`make check_network_policy_enforced` target so the answer is reproducible.

## Lessons from the central-storage rollout

Reviewed `deploys/central_storage/`, its README, `provision_namespace.sh`,
`deprovision_namespace.sh`, the transition script, the CI workflow, and the commits behind them
(`#119` central storage, `#120` post-transition updates). What was learned later, and how this plan
absorbs it from the start:

| What the central-storage work learned | Applied here |
| --- | --- |
| Concurrent provisioning raced (`tuple concurrently updated`); fixed with an advisory lock and kernel-chosen port-forward ports. | ACLs are one Secret key per namespace (atomic per key), and any port-forward uses a kernel-chosen port. No shared read-modify-write. |
| Replicas starting together raced on migrations; fixed with a lock. | No schema or init step: `XADD` creates streams, and nothing at startup needs exclusive access. Valkey connection setup must also be non-fatal at startup. |
| Cleanup (`deprovision_namespace.sh`) was added *after* provisioning, for smoke tests. | Deprovisioning is designed and built together with provisioning. |
| Provisioning *proves* isolation (the Silo user must not be able to create another bucket). | The ACL probe set described above, run before the Secret is written. |
| Credentials are generated randomly, never checked in, and admin Secrets are never regenerated if they exist. | Same for `rellm-central-valkey-credentials`. `deploys/Makefile`'s `get_all_storage_credentials` has a hard-coded list (`storage_credential_secrets`): add the new Secrets (`rellm-central-valkey-credentials`, `rellm-central-valkey`) so the password-manager export stays complete. |
| CI deploys by image tag only (`set_backend_images.sh`); manifest changes need a manual rollout, and the `manifest_change_notice` job warns about them. | Adding `VALKEY_*` env vars **is** a manifest change. The new `central_storage/k8s` manifest and edited server manifests will trigger that notice; the rollout is `NAMESPACE=<ns> make update_internal_central_data_backend` per namespace. The optional `secretKeyRef`s make the rollout order forgiving. |
| After a rollout replaces `rellm` pods, Traefik's TLS-passthrough routing can wedge on stale pod IPs; the transition script bounces Traefik (briefly interrupting **every** domain). | Rolling the new env vars to each namespace triggers this. Batch the Valkey env rollout with any other pending manifest changes and bounce Traefik once (the `--no-traefik-bounce` convention for all but the last). |
| Legacy namespaces predate each new convention (`adopt_legacy_data_credentials.sh`). | Namespaces already on central storage need a backfill step for the Valkey slice; legacy per-namespace-storage namespaces can opt in the same way. |
| Documentation drifted (the README is explicit about what is "Not covered"). | Update `central_storage/README.md` (new component, credentials and isolation section, NetworkPolicy note), `deploys/README.md` one-time setup, `docs/architecture/*.dot` + `make graphs` (diagrams show Postgres/Silo), and `docs/rellm_*.sh`; and the [warning checklist](#where-this-warning-must-appear). |
| PVC limits are the original reason central storage exists. | Valkey adds **zero** PVCs by design, which is exactly why its users must live in a Secret. |

## Elm ServerLogsTab (final step)

Planned, not started, and deliberately the **last** implementation step: it needs the RPC, the writer
and a running Valkey underneath it. Keep it simple and lightweight.

### Where it goes

`Components/Pages/ServerInformationPage.elm` composes one tab module per tab (`AboutTab`, `ThemeTab`,
`SettingsTab`, `FederationTab`, `CdnTab`, `ContactIntegrationsTab`, `MarketTab`, `ClusterTab`). Add
`Components/Pages/ServerInformationPage/ServerLogsTab.elm` and a `TabServerLogs` **immediately right
of `TabCluster`**, which means last in the tab bar (today: About, Theme, Settings, Federation, then for
admins Market, Contact Integrations, CDN, Cluster). Following the existing per-tab pattern:

- `Tab` union, `tabParam`/`tabFromParam` (`"server-logs"`), `tabIndex` (the slide direction depends on
  it), the `Model`/`Msg` fields (`serverLogsTab`, `ServerLogsTabMsg`), `init`, `update`, `view`. The
  tab-bar label can be just "Logs".
- An `activateServerLogsTab`, like `activateClusterTab`, that starts the first fetch when the tab
  becomes active (including when it's the tab named by the URL on load).
- `subscriptions` already batches per-tab subscriptions; the poll tick is added there and is active
  **only while `activeTab == TabServerLogs`**.
- **Visibility is gated on holding `VIEW_SERVER_LOGS`**, not on being an admin: the permission is not
  implied by `ADMIN`, so don't just put the tab inside the existing `adminAccountFor` branch of
  `tabBar`. (`ClusterTab` already does `List.member EDITCLUSTERSETTINGS account.permissions`; do the
  analogous check on the account for `targetHost`.) Without the permission the tab simply isn't in the
  bar, and a `?tab=server-logs` link falls back as for any unavailable tab.

### What it shows

- **At the top, one button that opens a dropdown of four checkboxes**: *All Logs*, *Server Logs*,
  *Job Logs*, *Preview Generator Logs*. See [the source picker](#the-source-picker) below.
- **A scrollable log area below**, one line per entry: time, a small source tag (and pod for the
  `rellm` replicas), then the message. Monospace; the message goes through an ANSI color parser (see
  [Color](#color)) and is never rendered as raw HTML. The source tag is only worth showing
  when more than one source is selected.
- Keep the client buffer bounded (e.g. the newest ~2,000 lines; drop from the top).
- Auto-scroll to the bottom *unless the user has scrolled up*; scrolling back to the bottom resumes
  following.
- Poll about every 2 s while the tab is active; if the response has `has_more`, poll again
  immediately. Pause polling when the browser tab is hidden (new `Browser.Events` work; no page does
  this today).
- A `gap` response inserts a "some lines are missing" marker line.
- Inline states for the errors in the [API table](#api): "not configured" and "unavailable" are
  informational messages in the log area, not failures.
- "Streaming" is polling; there is no server stream.

### The source picker

**State.** Three booleans (or one small record): `server`, `jobs`, `previewGenerator`. Default: all
three on. **"All Logs" is derived, never stored**, so it can't drift out of sync with the other three.
All three off is a legal state.

**How the checkboxes toggle one another:**

| Action | Result |
| --- | --- |
| Tick/untick *Server Logs*, *Job Logs* or *Preview Generator Logs* | toggles only that source |
| *All Logs* shows as ticked | exactly when all three sources are selected (so it ticks itself when you tick the last one, and unticks itself when you untick any) |
| Click *All Logs* while not all three are selected | selects all three |
| Click *All Logs* while all three are selected | selects none |

(Optional nicety, not needed for v1: show *All Logs* as indeterminate when only some are selected.)

**The button's text is exactly one of these eight strings** (sources always named in the order Server,
Job, Preview Generator):

| Server | Job | Preview Generator | Button text |
| :-: | :-: | :-: | --- |
| on | on | on | `All Logs` |
| on | off | off | `Server Logs` |
| off | on | off | `Job Logs` |
| off | off | on | `Preview Generator Logs` |
| on | on | off | `Server & Job Logs` |
| on | off | on | `Server & Preview Generator Logs` |
| off | on | on | `Job & Preview Generator Logs` |
| off | off | off | `No Logs Selected` |

Keep the label, the toggle rules and the mapping to request `sources` as small **pure functions** with
`elm-test` cases (all eight label combinations; each toggle rule), since that's where this UI can
quietly go wrong.

**What gets sent:**

- **With nothing selected, send no request at all** and show "Select at least one log source" in the
  log area. In the API an *empty* `sources` list means *all* sources, so sending the empty selection
  would show everything under a "No Logs Selected" label. This is the main trap in this UI.
- With "All Logs" selected, send the three sources **explicitly**, not an empty list: a source added in
  the future would otherwise appear under "All Logs" without having a checkbox of its own.
- **Any selection change resets the view**: empty cursor, clear the buffer (a cursor is only valid for
  the same set of sources; see the API contract), and fetch afresh. Tag each request with the selection
  it was made for and **discard a response that doesn't match the current selection**, or a slow
  response for the previous selection will repopulate the cleared log.

**The dropdown itself.** There's no reusable dropdown in `UI/` (the existing ones are
`.navbar`-anchored panels driven from `Shared`), so build the smallest thing that works:

- The button toggles an open/closed flag in `ServerLogsTab`'s own model.
- Close on outside click with a transparent full-viewport click-catcher behind the open menu (no global
  subscription needed), and on `Escape` via a `Browser.Events.onKeyDown` subscription that exists only
  while the menu is open (`MediaViewerPanel`/`AudioPlayerPanel` already do the Escape handling).
- Ticking a checkbox does **not** close the menu; the user usually toggles more than one.
- Make it usable on a phone (the SPA is used there): full-width menu, tap-sized rows.
- Not persisted across page loads in v1.

### Color

**Decided: preserve ANSI color end to end, and render it in Elm.** Elm can do this with plain string
processing (or an existing package; `vito/elm-ansi` is the one Concourse's web UI uses, to be checked
for Elm 0.19.3 compatibility and license), rendering through `Html` spans so there is no HTML
injection.

- **Writer:** keep SGR sequences (`ESC [ digits/semicolons m`) and strip every other control sequence
  (cursor movement, OSC, etc.). Bound the length of a sequence and the number of them per line; never
  truncate inside one.
- **What the colored text is:** `level`, `pod` and the timestamp travel as separate structured fields
  (the level also picks the stream bucket), so the UI builds its own `[timestamp LEVEL source]` prefix
  in the same shape as the stdout format and colors the level badge from the `level` field, which
  keeps it theme-aware. The `text` field is the message, and any SGR in it is rendered by the parser.
  Both together give "good color in all logs" without depending on the app emitting escapes for the
  level itself.
- **Elm parser:** support the basic and bright 8/16 colors, bold/dim/underline/italic and reset
  (`0`, `22`, `39`, ...); drop anything unrecognized (256-color and truecolor are optional). State is
  per line (a line never inherits style from the previous one), so an unterminated sequence can't bleed.
- **Theme:** don't paint raw ANSI palette values. Map each SGR color to a CSS class whose color is
  tuned for the light and dark themes (ANSI yellow on white, or dark blue on black, is unreadable).
- **Source of the escapes:** nothing in the apps emits them today except the log *format*:
  `env_logger` colors only the level, and only when it believes it is writing to a terminal (stdout isn't
  one in the cluster). See [Preparatory: job log format](#preparatory-job-log-format) for how that gets
  turned on, and `NO_COLOR` should still be honored.
- The `ServerLogLine.text` proto doc must say SGR is preserved and everything else stripped.

## Preparatory: job log format

**Landed.** A small change that came before any of the Valkey work, and gives the Valkey path its model.

**Before this change** (`backend/src/lib.rs`): `init_bin_logging()`, called by *every* bin, formats lines with no
timestamp, no level and no target; `init_service_logging()` (the `rellm` server) uses `env_logger`'s
default `[2026-10-05T12:00:00Z INFO  rellm::mod] message`, uncolored because stdout isn't a terminal.
`background_jobs.sh` pipes each job through `_background_jobs_label`, adding `[job_name] `. The preview
generator pod has its own wrapper, `preview_generator_job.sh`, which adds no label at all.

**Goal:** job lines look like the server's: `[2026-10-05T12:00:00Z INFO  delete_expired_tokens] message`,
with the level colored (INFO green, WARN yellow, ERROR red, DEBUG blue, TRACE cyan, `env_logger`'s own
defaults).

**What can be done in only `background_jobs.sh` and `bin/*.rs`:** not the level. The bins' output has
no level in it (`format_level(false)`), so a shell filter can add a timestamp and a label but never the
level or its color. The only way to do it inside `bin/*.rs` alone is replacing `init_bin_logging()` in
each job bin with the same inline formatter (8 job bins plus `generate_link_preview_images`, 9 copies
of ~15 lines that will drift).

**What was done (one function in `lib.rs`, opt-in by environment):**

- `init_bin_logging()` keeps today's format by default and switches to the job format **only when
  `RELLM_LOG_JOB_NAME` is set**. The format is a custom `env_logger` formatter: `[<RFC 3339 UTC time>
  <LEVEL padded to 5> <job name>] <message>`, color forced on (`write_style(Always)`) unless `NO_COLOR`
  is set. No bin file needs to change; they already call `init_bin_logging()`.
- `background_jobs.sh` and `preview_generator_job.sh` set `RELLM_LOG_JOB_NAME=<name>` for the job they
  run. The shell-side `[name]` prefix then only needs to apply to lines that are *not* already formatted
  (panic text on stderr, `cargo run` build output, stray `println!`), and the wrapper's own messages
  (`[background_jobs] running ...`, `... failed`) should use the same `[time LEVEL name]` shape with
  `printf` escapes (failure as ERROR/red).
- **Why opt-in, not "just change `init_bin_logging`":** several bins are CLI tools whose *result is
  printed through `log::info!`*: `to_proto_id` and `to_db_id` print the converted ID, and
  `set_permission` is run by an operator. Their output is deliberately bare today. A global change
  would put a timestamp, a level and ANSI escapes in front of the answer, which breaks copy/paste and
  any script parsing it.
- **Not done (follow-ups):**
  - A panic hook in the job format (logging the panic at ERROR through the same formatter), so panics
    aren't just `[name]`-labeled stderr text. The Valkey writer needs the same hook anyway.
  - `init_service_logging()` (the `rellm` server) getting the same forced color, so "good color in all
    logs" holds for the server; it is also where the Valkey tee goes.
- **Valkey interplay:** the jobs are **short-lived processes** (each run starts, logs, exits). A
  batching Valkey writer must be flushed before a job exits or its last lines are lost; that means
  `init_bin_logging()` returning a guard held in `main`, or the bin sink writing synchronously. Decide
  when the writer is built.

**Where it lives:** `init_bin_logging()` / `init_job_logging()` in `backend/src/lib.rs` (the opt-in is
the `RELLM_LOG_JOB_NAME` environment variable, `JOB_NAME_ENV_VAR`), `background_jobs.sh` and
`preview_generator_job.sh`. The wrappers' own messages (`running ...`, `... failed`) use the same shape
(failures as red ERROR on stderr). Verified: default output of `to_proto_id` is still bare; with the
variable set it prints `[2026-10-05T18:42:23Z INFO  demo_job] JnrP9` with the level colored; `NO_COLOR`
and an empty variable are honored; the shell helpers behave under macOS's bash 3.2.

**Notes:**

- **Source checkouts only:** `background_jobs.sh` resolves each job to a prebuilt binary beside the
  script (the Docker image and the Homebrew/Linux packages always have one), and only falls back to a
  source build when it finds none. In that case it runs `cargo build --quiet` first, discards the
  output, and runs `target/debug/<job>` itself, so compiler warnings and `Finished`/`Running` don't
  end up in the job log (`cargo run --quiet` still replays warnings, and hiding them with compiler
  flags would invalidate the normal build cache). End users never hit this path.
- **Log files and syslog:** the Homebrew/Linux launchers (`docs/rellm_*.sh`) can send job output to
  `RELLM_LOG_FILE` or syslog (`RELLM_SYSLOG=1`), which now receive the level's ANSI escape codes.
  `NO_COLOR=1` turns them off, and the launchers' comments say so. Stripping them in the launchers
  instead is possible but not done.
- What the remaining `[job_name]` prefix still covers: output that isn't a `log` record (panic text,
  stray `println!`, continuation lines of multi-line messages).

## Implementation order

Suggested, each step independently shippable (and dormant until the next):

1. ✅ `VIEW_SERVER_LOGS` permission (done).
2. ✅ [Job log format](#preparatory-job-log-format) (timestamp, level, color) (done).
3. Protos: `server_logs.proto` (long-form docs as described under [API](#api)), the import and `rpc` in
   `rellm.proto`, `docs/Makefile` list; regenerate everything (`make`). The backend needs a
   (permission-checked, `UNIMPLEMENTED`) handler for the build to pass.
4. Central Valkey deployment: manifest, `create_central_valkey`, the Secret-held ACL file with its
   initContainer, credentials Secrets, local dev target; docs including the warning checklist.
5. Per-namespace provisioning/deprovisioning scripts with their probes, plus the backfill.
6. The writer (`log::Log` tee) behind the dormant `VALKEY_*` env vars; then the reader and the real
   `GetServerLogs`.
7. NetworkPolicy check and policy (can happen any time after 3).
8. Manifest env rollout per namespace (see [Rollout order](#rollout-order)).
9. **The Elm `ServerLogsTab`**, last.

## Rollout order

1. Ship the backend/Elm change with the feature dormant (no `VALKEY_*` set). CI's image-only deploy is
   safe: behavior is unchanged.
2. `make create_central_valkey` (once per cluster; `create_central_storage` includes it for new
   clusters). Verify with `get_central_storage_all`, a `valkey-cli ping` using the `probe` user, and
   `verify_central_valkey_acl`.
3. Run `check_network_policy_enforced`. If enforced, apply the `rellm-storage` NetworkPolicy covering
   Postgres, Silo and Valkey; if not, record that in the central-storage README's "Not covered".
4. Per namespace: provision its Valkey slice (new namespaces get it from `provision_namespace.sh`;
   existing ones use the backfill target). Verify with the script's own probes.
5. Roll the manifests (`update_internal_central_data_backend`, or the equivalent for non-central
   namespaces). Bounce Traefik once at the end.
6. `set_permission <username> VIEW_SERVER_LOGS on` for the intended user(s); smoke-test the `ServerLogsTab`
   against the first namespace before the rest. Remember permission-gated smoke tests need a granted
   account.

## Risks

Condensed; most-severe first.

1. **Secrets and personal data in logs.** Valkey is unencrypted at rest and in transit by default.
   Redact at write time, strip control characters (other than SGR color), render lines as text spans (never raw HTML), and treat the stream
   as sensitive. `RUST_BACKTRACE=full` panics can echo configuration, so check what the backend logs
   (anything that prints a DB/object-storage URL or config struct) before shipping.
2. **Cross-site leakage via the shared instance.** The central design's main risk. Mitigated by
   per-namespace ACL users with key-pattern scoping, `default` disabled, the provisioning probes, and
   (if enforced) a NetworkPolicy. Test with a deliberate negative test, not just the happy path.
3. **Users that exist only in Valkey (not in the ACL Secret) vanish on restart**, silently stopping
   logs for that site. This is the failure the [top-of-doc warning](#planning-getserverlogs-rpc-via-central-valkey)
   exists for; `verify_central_valkey_acl` is the guard.
4. **Eviction deletes a whole stream; a full instance fails all writes.** `noeviction` plus `MAXLEN`
   plus the line-length cap bound memory; alert on memory use.
5. **A log storm erases the cause.** Separate WARN+ streams; consider per-source rate limiting with a
   "N lines dropped" marker.
6. **Cursor skip bug** (reading streams non-atomically). Use `MULTI`/`EXEC`; add a test.
7. **Ephemeral by design.** A Valkey restart or reschedule wipes the buffers, sometimes mid-incident.
   Say so in the UI ("recent logs only; may reset"). `kubectl logs` is the fallback.
8. **Feedback loop and backpressure in the writer.** Exclude the client's own logs; bounded channel;
   drop on overflow; never block or fail the app.
9. **Coverage gaps.** Only `log::` output is captured; native-library output, Traefik and Stalwart
   aren't. Panics need the panic hook.
10. **Single point of failure for the feature, not the app.** One pod, no HA. Acceptable because
    writers are fail-open.
11. **Licensing/supply chain.** Valkey is BSD; pin the image tag and update deliberately.
12. **Short-lived job processes can lose their last log lines** if the batching writer isn't flushed
    before they exit (see [Preparatory: job log format](#preparatory-job-log-format)).
13. **Rolling the env vars** replaces every site's `rellm` pods and needs a Traefik bounce (see
    lessons above).

## Open questions

1. **Redaction scope:** which patterns, and where does the list live so it's testable.
2. **Retention follow-up** (explicitly deferred): a `rellm-jobs` consumer (stream consumer group)
   archiving to time-keyed objects in the namespace's bucket. Nothing in this design blocks it, and
   the earlier "DB pointer table" idea would fit there if per-segment metadata is wanted.
3. **Server streaming follow-up:** if ~2 s polling isn't enough, wrapping `XREAD BLOCK` in a
   server-streaming RPC is possible; it needs a dedicated Valkey connection per tailer (blocking
   commands can't share a multiplexed connection) and a check of Traefik idle timeouts.

Resolved: caps are per source; cursor/limit are added to the request; ACL users live in a Secret
(not a PVC); ANSI color is preserved and rendered in Elm.

## Pre-existing issues found while researching

Found while following the hand-maintained-list gotcha; fixed alongside the permission because they're
part of it being "complete":

- `frontends/elm-spa/src/Shared/AccountsPanel/RellmAccounts.elm` `permissionFromInt` maps permission
  numbers by hand and **had no case for `10003`**: `EDIT_SERVER_MEDIA_ALLOCATION` fell through to
  `PermissionUnrecognized_`, so for accounts decoded from persisted storage,
  `List.member EDITSERVERMEDIAALLOCATION account.permissions` (used in `SettingsTab.elm`) could be
  false even for a user who has it. **Fixed** (`10003` added next to `10004`). Whether accounts are
  always refreshed from the server after load (which would have masked it) was not checked.
