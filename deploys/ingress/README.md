# Rellm Ingress

A single shared [Traefik](https://traefik.io) ingress that lets many Rellm instances (each in its own namespace, each with its own domain, Postgres, object storage and Cert-Manager certs) share **one** external IP/LoadBalancer instead of one each. On most cloud providers a LoadBalancer/external IP is the most expensive part of running a small Rellm instance, so this is the difference between paying for `N` of them and paying for 1, no matter how many domains you host.

This whole setup is domain-agnostic and cluster-agnostic: nothing you type here ends up in a file this repo tracks in git (same principle as [the Cert-Manager setup](../generated_certs/README.md), which never commits your actual domain either).

## How it works

Your `rellm` backend already terminates its own TLS (see `create_internal_backend`/`update_internal_backend` in `../Makefile`, and `k8s/server_internal.yaml`) using the Cert-Manager certs set up per [`../generated_certs/README.md`](../generated_certs/README.md). This ingress does **not** re-terminate that TLS. Instead it reads the plaintext SNI hostname out of the TLS handshake's first message (the same mechanism that lets any single IP host multiple HTTPS sites) to decide which namespace's `rellm` Service to forward the still-encrypted bytes to, then gets out of the way. Your certs, your `rellm-generated-tls` secrets, and Cert-Manager's renewal all keep working completely untouched, in their existing per-namespace locations.

Plain HTTP (ports 80 and 8000) is routed the normal way, by `Host` header.

This controller also carries a plain TCP passthrough entrypoint on port 25 for the shared Stalwart mail server (see [`../email/README.md`](../email/README.md)) - unlike the ports above, there's nothing to route *between* there (Stalwart is cluster-wide, not per-namespace), so its `IngressRouteTCP` just catches everything with ``HostSNI(`*`)`` and forwards it straight through.

Because of this, a domain's routing config is a handful of small `IngressRoute`/`IngressRouteTCP` objects that live in *that domain's own namespace* (see `k8s/rellm-routes.template.yaml`), right next to its `rellm` Service - not in some central config. Traefik discovers them across every namespace automatically.

## One-time setup: install the shared controller

From this directory (or `deploys`, since the root `Makefile` has passthroughs - see below):

```bash
make create_ingress
```

This installs Traefik's CRDs (pinned to `TRAEFIK_VERSION` at the top of the `Makefile`) and the Traefik `Deployment`/`Service` itself, in the `traefik-ingress` namespace. It's completely generic - run it once per cluster, regardless of how many domains you plan to host.

Get its external IP with:

```bash
make get_ingress_external_ip
```

To tear the shared controller back down (leaving any per-domain routes in place, harmlessly inert, and without touching the Traefik CRDs - deleting those would delete every domain's routes across the whole cluster, not just the controller):

```bash
make remove_ingress
```

## Onboarding a domain

Once a namespace already has its own `rellm` backend, Postgres, object storage and Cert-Manager certs set up (i.e. you've already done the [Basic Deployment](../README.md#basic-deployment) for it) and it's currently using `server_external.yaml` (its own LoadBalancer), you can move it behind the shared ingress:

```bash
NAMESPACE=mynamespace DOMAIN=my.domain.example.com make add_ingress_domain
```

**Before touching DNS**, validate the route directly against the shared ingress's IP (from `make get_ingress_external_ip`), for all 4 ports:

```bash
curl --resolve my.domain.example.com:443:<ingress-ip> https://my.domain.example.com/
curl --resolve my.domain.example.com:80:<ingress-ip>  http://my.domain.example.com/
grpcurl -authority my.domain.example.com <ingress-ip>:27707 list
```

Once that all looks right, point `my.domain.example.com`'s DNS A record at the shared ingress's IP. Only *after* traffic has actually moved over (watch it drain from the old LoadBalancer, or just wait out the old DNS TTL), switch that namespace off its own LoadBalancer to reclaim its cost:

```bash
NAMESPACE=mynamespace make update_internal_backend
```

Doing this out of order - switching off the old LoadBalancer before DNS has actually moved - will take the site down until DNS propagates, so don't skip the validation step above.

### Fronting a domain with a CDN/proxy (e.g. Cloudflare)

If something sits in front of Traefik and connects to it under a *different* hostname than `DOMAIN` - e.g. Cloudflare proxying `jonline.io` to an origin that's actually `jonline.io.getj.online` - you need to tell Traefik about that extra hostname too, or it won't recognize the connection (SNI passthrough on 443/27707 and Host-routing on 80/8000 both key off whatever hostname is presented *to Traefik*, not the one your Cert-Manager certs were issued for). Pass it via `EXTRA_DOMAINS` (space-separated if there's more than one):

```bash
NAMESPACE=mynamespace DOMAIN=my.domain.example.com EXTRA_DOMAINS=my.cdn-fronted-domain.com make add_ingress_domain
```

This is unrelated to TLS certs - your origin keeps presenting its one Cert-Manager cert for `DOMAIN` regardless of which hostname was used to reach it, so a CDN validating that cert against its own hostname (e.g. Cloudflare's "Full (Strict)" mode) will see a mismatch and fail; using the CDN's "Full" (encrypt, don't validate) mode, or otherwise letting the CDN accept a non-matching origin cert, is the expected way to run this setup.

To see every namespace/domain currently wired up to the shared ingress (queried live from the cluster, not from local files):

```bash
make list_ingress_domains
```

To remove a domain from the shared ingress (e.g. to move it back to its own LoadBalancer):

```bash
NAMESPACE=mynamespace DOMAIN=my.domain.example.com make remove_ingress_domain
```
