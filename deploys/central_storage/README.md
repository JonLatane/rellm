# Rellm Central Storage

A single shared Postgres + [Silo](https://github.com/pgsty/silo) (S3-compatible object storage)
instance that many Rellm namespaces can point at instead of each provisioning their own.

## Why

A normal Rellm deploy (`create_backend_data` in `../Makefile`) provisions its own Postgres and
object storage StatefulSet per namespace -- 2 PVCs each. Most managed Kubernetes offerings cap how
many PVCs a cluster can attach at all (DigitalOcean's DOKS: 15), so that runs out fast once you're
hosting more than half a dozen domains. This deploy uses exactly **2** PVCs total, no matter how
many namespaces point at it, by giving each namespace its own database (in the shared Postgres)
and its own bucket (in the shared object storage) instead of its own instance of either.

This is purely additive -- it doesn't touch or migrate any existing per-namespace deploy. Onboard
new namespaces onto it going forward; existing ones can stay exactly as they are.

## One-time setup: create the shared instances

From this directory (or `deploys`, since `../Makefile` has passthroughs -- see below):

```bash
make create_central_storage
```

This creates the `rellm-storage` namespace (override with `NAMESPACE=...`, though nearly every
other target in this repo assumes the `rellm-storage` default -- see `../Makefile`'s
`STORAGE_NAMESPACE`) and two StatefulSets in it: `rellm-central-postgres` and
`rellm-central-object-storage`. Run this once per cluster.

`update_central_storage`, `restart_central_storage`, `delete_central_storage` and
`get_central_storage_all` mirror `create_central_storage` for the usual update/restart/teardown/
inspect lifecycle -- see the `Makefile` for the finer-grained `*_postgres`/`*_object_storage`
targets these wrap (e.g. `delete_central_postgres_pvc`, which -- like its per-namespace
counterpart in `../Makefile` -- is deliberately never bundled into a `delete_*` target, since the
underlying volume's `reclaimPolicy: Retain` means data survives either way, but releasing the PVC
orphans the volume until manually reclaimed).

## Onboarding a namespace

Once the shared instances above exist, point a **new** namespace at them from `deploys` (not this
directory) with:

```bash
NAMESPACE=mynewsite make create_backend_central_data create_internal_central_data_backend
```

* `create_backend_central_data` runs [`provision_namespace.sh`](./provision_namespace.sh): it creates
  a Postgres database + login role and an object storage bucket + user, all named `mynewsite`, each
  restricted to only that data (see [Credentials and isolation](#credentials-and-isolation)), and
  stores freshly generated random credentials for both in a `rellm-central-data` Secret in the
  `mynewsite` namespace. Needs `mc` (`brew install minio/stable/mc`) and `openssl` locally.
  Re-run with `ARGS=--reset` to drop and redo a half-finished attempt.
* `create_internal_central_data_backend` deploys `rellm`/`rellm-jobs`/the preview generator into
  the `mynewsite` namespace, using `../k8s/server_internal_central_data.yaml` and
  `../k8s/preview_generator_central_data.yaml` (templated with `${NAMESPACE}`/
  `${STORAGE_NAMESPACE}`, generated to a gitignored `.generated.yaml` -- same mechanism as
  `../ingress`'s per-domain routes) instead of `create_internal_backend`'s
  `k8s/server_internal.yaml`.

From there, TLS certs (`../generated_certs`), the shared ingress (`../ingress`) and shared mail
(`../email`) all work exactly as they do for any other namespace -- `mynewsite`'s `rellm` Service
looks the same either way, only where its data lives differs.

## Transitioning an existing namespace

To move a namespace that already has its own Postgres/object storage onto the shared instances:

```bash
NAMESPACE=bullcitysocial make transition_backend_to_central_data
# or directly: ./transition_jonline_namespace_to_central_storage.sh bullcitysocial
```

**The site is down for the duration** (it scales `rellm`/`rellm-jobs`/`rellm-preview-generator` to 0, copies the database with `pg_dump | psql` and the bucket with `mc mirror`, verifies both, applies the central-data manifests, and waits for healthy pods). The namespace's old Postgres/object storage and their PVCs are left completely untouched and running, so you can verify the site and roll back. See the script's header for flags (`--reset-target`, `--repo-images`, ...) and prerequisites (`mc`).

CI needs no change per namespace: once the script has applied the switch, the next deploy sees the namespace is on central storage and applies the central-data manifests (see [CI](#ci)).

Once you've verified the site, free the old PVCs (this refuses to run unless the namespace really is on central storage):

```bash
NAMESPACE=bullcitysocial CONFIRM=bullcitysocial make delete_backend_data_pvcs
```

The underlying volumes are retained (`reclaimPolicy: Retain`); the target prints their PV names so you can delete them, and then the cloud volumes, yourself.

## Removing a namespace from central storage

`NAMESPACE=mynewsite CONFIRM=mynewsite make delete_backend_central_data` (or
[`deprovision_namespace.sh`](./deprovision_namespace.sh)) is the reverse of provisioning: it
**permanently** deletes the namespace's database and role, its bucket *and every object in it*, its
Silo user/policy and its `rellm-central-data` Secret. Use it to clean up a smoke test or retire a
site. It refuses while a `rellm` Deployment in that namespace still runs against central storage --
delete the site first (`kubectl delete namespace mynewsite`); it's fine for the namespace to
already be gone. Safe to re-run.

## Credentials and isolation

Nothing secret is checked in. `create_central_storage` generates random admin credentials for the
shared instances into Secrets in `rellm-storage` (`rellm-central-postgres-credentials`,
`rellm-central-object-storage-credentials`) -- once, never rotated behind your back -- and only
`provision_namespace.sh` uses them. Each site instead gets its own credentials, named after its
namespace and stored in that namespace's `rellm-central-data` Secret (read by
`server_internal_central_data.yaml`/`preview_generator_central_data.yaml` via `secretKeyRef`):

* **Postgres:** a `LOGIN` role named after the namespace -- `NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS`, `CONNECTION LIMIT 30` -- that owns a database of the same name.
  `PUBLIC`'s `CONNECT` on that database is revoked, so no other site's role can even connect to it.
  Network connections require the password (scram-sha-256). `max_connections` is raised to 200
  (the backend keeps at most 4 connections per server process and 1 per job, see
  `backend/src/db_connection.rs`).
* **Object storage:** a user named after the namespace with a policy (`rellm-<namespace>`) that
  allows `s3:*` on only that namespace's bucket. `provision_namespace.sh` proves it before
  finishing: the new user must be able to write its own bucket and must *not* be able to create
  another.

Not covered: there is no NetworkPolicy, so any pod in the cluster can still *attempt* to reach the
shared instances (it just can't authenticate as another site), and anyone with `kubectl exec` on the
Postgres pod is trusted (local socket connections are `trust`, as in the stock image).

## CI

`.github/workflows/server_ci_cd.yml` picks each namespace's manifests with
`deploys/select_backend_manifest.sh`, based on what the namespace's live `rellm` Deployment is
running: if its `DATABASE_URL` comes from the `rellm-central-data` Secret, CI applies the generated
central-data manifests; otherwise `server_internal.yaml`/`preview_generator.yaml`. A namespace
therefore only switches when the transition script applies the switch -- provisioning alone never
changes what CI deploys. The version bump in CI is applied to both sets of manifests.
