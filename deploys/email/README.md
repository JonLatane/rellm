# Rellm Email

A single shared [Stalwart](https://stalw.art) mail server that lets your `rellm` instances receive mail at `<username>@yourdomain`, without teaching any of them to speak SMTP. Stalwart does the actual internet-facing mail protocol/spam-fighting work; it never stores a mailbox. Instead, once it accepts a message for one of your onboarded domains, it hands the raw message straight to that domain's own namespace over an internal-only HTTP endpoint (`POST /email` on port 27705 - see `backend/src/web/email.rs`), which parses it and stores it against the right Rellm user(s).

## How it works

```
sender's MTA -> DNS MX lookup for yourdomain.com -> Traefik (:25, shared LoadBalancer)
                                                        |
                                     plain TCP passthrough, HostSNI(`*`) catch-all --
                                     Stalwart is the only possible destination, so
                                     there's nothing to route *between* (see below)
                                                        |
                                                        v
                                                  Stalwart (ClusterIP)
                                                        |
                                              accepts mail for onboarded domains,
                                              fires an MTA Hook at the DATA stage
                                                        |
                                                        v
                                   POST http://rellm.<namespace>.svc.cluster.local:27705/email
                                   (body: Stalwart's MTA Hook JSON - envelope.to/from,
                                    message.headers, message.contents; NOT a raw MIME stream)
                                                        |
                                                        v
                              that namespace's `rellm` backend parses it, stores the raw
                              message in object storage, and indexes it in Postgres per recipient
```

Because Stalwart is the one thing that has to be a well-behaved, spam-resistant internet-facing SMTP server, this is a **single shared component per cluster** - like `deploys/ingress`'s Traefik, not like each namespace's own `rellm` Deployment. Unlike `rellm`, though, it sits *behind* that same shared Traefik ingress rather than getting its own LoadBalancer: `deploys/ingress` has to peek at the TLS SNI on 443/27707 to decide which of several namespaces to forward to, but there's no such decision for SMTP - Stalwart is the only possible destination cluster-wide (it does its own per-domain acceptance internally, after Traefik hands it the connection). So it's wired up as a plain TCP passthrough on a dedicated `smtp` entrypoint (port 25) with a catch-all ``HostSNI(`*`)`` route, requiring nothing from Traefik beyond "forward every byte" - see `../ingress/k8s/traefik.yaml` and `k8s/stalwart.yaml`'s `IngressRouteTCP`. STARTTLS is transparent to this: it just upgrades the same already-routed connection in place, it doesn't open a new one Traefik would need to re-route.

This means **`deploys/ingress`'s shared controller must already be installed** (`make create_ingress`) before `create_email` below is useful - Stalwart has no external IP of its own.

Port 27705 on each `rellm` Deployment is **internal-only** - it has no authentication of its own and trusts whatever calls it completely. It's deliberately absent from `server_external.yaml`'s (LoadBalancer) Service; only `server_internal.yaml`/`server_internal_insecure.yaml` (ClusterIP) expose it, and only inside the cluster. If your threat model wants more than "not internet-routable," add a `NetworkPolicy` in each domain's namespace restricting port 27705 to pods in the `rellm-email` namespace.

## One-time setup: install the shared controller

Pre-code Stalwart's initial admin credentials (skip this and it falls back to a random one-time password logged via `kubectl logs`, but `add_email_domain`/etc. below need to know the password, so set one):

```bash
ADMIN_PASSWORD=correct-horse-battery-staple make create_email_admin_secret
```

Then boot the controller itself:

```bash
make create_email
```

This installs Stalwart (`Deployment`, two `ClusterIP` Services, a `PersistentVolumeClaim`, and an `IngressRouteTCP` onto the shared Traefik controller) into its own `rellm-email` namespace - see `k8s/stalwart.yaml`'s comments for what each piece is for, in particular:

* The `stalwart-data` PVC holds **Stalwart's own configuration** (accepted domains, MTA Hook definitions, DKIM keys, TLS state) and its in-flight message queue - not user mailboxes. Losing it means redoing a few minutes of setup, not losing anyone's mail, since accepted messages are handed off immediately and never stored here.
* Port 8080 (the admin UI / setup wizard) is deliberately `ClusterIP`-only, never a `LoadBalancer`. Reach it with:

  ```bash
  make deploy_email_admin_port_forward
  # then open http://localhost:8080
  ```
* On a fresh volume, Stalwart boots into a setup wizard - log in with the credentials from `create_email_admin_secret` above (or the random one-time password from `kubectl logs -n rellm-email deployment/stalwart` if you skipped it) and walk through hostname/storage/directory choices. Pick **RocksDB** for storage (there's no Postgres option provisioned here - see the PVC note above), and set logging to output to the **console** rather than a file, so `kubectl logs` actually shows something.

Get the shared ingress's external IP (what your MX records will point at - Stalwart no longer has an IP of its own) with:

```bash
make deploy_email_get_ip
```

## Onboarding a domain

Unlike `deploys/ingress`'s `add_ingress_domain`, this isn't a `kubectl apply` of generated YAML - Stalwart keeps its accepted-domains list and MTA Hook definitions in its own database. `add_email_domain`/`remove_email_domain`/`list_email_domains` script that database through Stalwart's REST Management API (its JMAP-based `x:Domain`/`x:MtaHook` extension objects; see [stalw.art/docs/api/management](https://stalw.art/docs/api/management/overview/)) instead of walking the admin UI by hand.

`add_email_domain`/`remove_email_domain`/`list_email_domains` need Stalwart's Management API reachable at `localhost:8080`, which is `ClusterIP`-only (same as the admin UI) - but you don't need to set that up yourself: each target checks the port first and, if nothing's there, starts `deploy_email_admin_port_forward` in the background for the duration of the call and stops it again afterward (only if it started it - an existing port-forward from another terminal is left running). Run `make deploy_email_admin_stop_port_forwarding` if you ever need to kill a stray one by hand.

```bash
NAMESPACE=mynamespace DOMAIN=my.domain.example.com make add_email_domain
```

This adds `my.domain.example.com` as an accepted domain and a `data`-stage MTA Hook scoped to it (via an `enable` expression matching `rcpt_domain`), pointed at that namespace's `rellm` Service. This has been exercised end-to-end against a live instance (`swaks` -> Stalwart -> the hook -> a stored [`Message`](https://rellm.org/docs/protocol#rellm-Message)) - but Stalwart's Management API can still evolve between releases, so if `add_email_domain`/`remove_email_domain` start failing, recheck them against your running version. `create` calls are not idempotent (Stalwart has no "get or create" for `x:Domain`/`x:MtaHook`) - re-running `add_email_domain` for a domain that already exists will either `notCreated`/`primaryKeyViolation` on the `Domain` (harmless) or pile up a duplicate `MtaHook` pointed at the same URL (harmless but untidy; both fire per message). Verify with `make list_email_domains` before pointing real DNS at a new domain.

Stalwart's `data`-stage MTA Hook is a JSON POST, not a raw MIME stream with a custom header - see `backend/src/web/email.rs`'s doc comment and <https://stalw.art/docs/mta/filter/mtahooks/> for the exact shape. Recipients come from the JSON body's `envelope.to` addresses (deliberately the SMTP envelope, not the message's `To`/`Cc` headers, since that's the only place Bcc'd recipients show up at all); there is no `httpHeaders` configuration needed on the `MtaHook` object for this to work.

If mail gets a `550 5.1.2 Relay not allowed` even though the domain shows up in `list_email_domains` with `allowRelaying: true`, Stalwart may have cached a negative "no such domain" lookup from before the domain existed - `make deploy_email_restart` flushes it.

### DNS

Per domain, still in Cloudflare (or wherever it's hosted):

| Record | Example | Notes |
|---|---|---|
| MX | `my.domain.example.com. MX 10 <target>.` | `<target>` resolves to the shared ingress's IP from `make deploy_email_get_ip` - the same IP your other domains' 443/27707 records may already point at. |
| A/AAAA (`<target>`) | `<target> A <ingress-ip>` | **Must be DNS-only ("grey cloud")** if you're on Cloudflare - the proxy doesn't handle SMTP at all, only HTTP(S). |
| SPF | `my.domain.example.com. TXT "v=spf1 mx ~all"` | Helps other servers trust anything you bounce, even before you're sending real outbound mail. |
| DMARC | `_dmarc.my.domain.example.com TXT "v=DMARC1; p=none; rua=mailto:you@..."` | Start at `p=none` (report-only). |

Also confirm your hosting/cloud provider allows inbound traffic on port 25 - some block it by default even for receive-only use, and require a support ticket to lift it.

### Testing

Validate mail actually reaches your namespace *before* touching real DNS, by connecting straight to the ingress IP - this isolates "does Stalwart accept mail for this domain" from "is DNS wired up right":

1. **Confirm the port's even reachable** (this is a Traefik/firewall check, independent of Stalwart):

   ```bash
   openssl s_client -connect <ingress-ip>:25 -crlf
   ```

   You should see Stalwart's `220 ... ESMTP` banner. If it hangs, it's `deploys/ingress`'s `IngressRouteTCP`/firewall, not Stalwart.

2. **Send a test message** with `swaks`, bypassing MX/DNS by pointing straight at the IP:

   ```bash
   swaks --to test@<target> --server <ingress-ip> --header "Subject: Test" --body "Test message."
   ```

   Always pass `--header`/`--body` explicitly - without them, `swaks` may decide stdin isn't a real terminal and sit waiting for you to type the message body instead of using its canned default (end manual entry with a lone `.` or `Ctrl-D` if you get stuck here).

3. **Watch both ends while it sends:**

   ```bash
   kubectl logs -f deployment/stalwart -n rellm-email     # did Stalwart accept it / fire the hook?
   kubectl logs -f deployment/rellm -n mynamespace         # did the hook's POST /email land?
   ```

If it doesn't just work, the SMTP response usually tells you exactly which layer to blame:

| Response | Cause | Fix |
| --- | --- | --- |
| `550 5.1.2 Relay not allowed.` | Stalwart doesn't think it owns this domain at all - either `add_email_domain` wasn't run/succeeded, or Stalwart cached an earlier "no such domain" lookup before the domain existed. | `make list_email_domains` to confirm it's actually there; if it is, `make deploy_email_restart` to flush Stalwart's in-memory domain cache (it caches negative lookups with a TTL) and retest. |
| `550 5.1.2 Mailbox does not exist.` | The domain is accepted, but Stalwart itself has no matching account/mailing list/catch-all for that address - expected, since Stalwart deliberately never has its own concept of `rellm` users. The `Domain` object needs `allowRelaying: true` so Stalwart accepts *any* recipient and defers the real "does this user exist" check downstream (`rellm`'s backend silently drops unmatched recipients - see `backend/src/web/email.rs`). `add_email_domain` sets this automatically for new domains; for one created before that existed, patch it directly (`x:Domain/set` `update`, not `create` - `create` on an existing domain just no-ops with `primaryKeyViolation`). | `make deploy_email_restart` after patching, same caching reason as above. |
| Hangs ~30s after `DATA`, then `451 4.3.5 Unable to accept message at this time.` | Everything on the Stalwart side is correct - it accepted the mail and fired the MTA Hook, which then timed out (hook's default 30s timeout, `tempFailOnError: true`) trying to reach `http://rellm.<namespace>.svc.cluster.local:27705/email`. Nothing's listening there yet. | Deploy `rellm` with the port-27705 internal endpoint to that namespace, then retest - this is actually a good sign, it confirms the whole chain up to the handoff works. |

Once a test message with a *real* onboarded username actually lands (check the recipient's inbox, or `email_messages`/`email_message_recipients` in that namespace's Postgres), you're ready to point real DNS at it.

## Removing a domain / tearing down

Remove a domain's acceptance + MTA Hook through the same admin UI you added it in, then remove its DNS records. To remove the shared controller entirely:

```bash
make remove_email
```
