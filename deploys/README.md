# Rellm Deploys

- [Rellm Deploys](#rellm-deploys)
  - [End-User Deployment](#end-user-deployment)
    - [Basic Deployment](#basic-deployment)
      - [Deploying to namespaces other than `rellm`](#deploying-to-namespaces-other-than-rellm)
      - [Credentials](#credentials)
    - [Validating your deployment](#validating-your-deployment)
      - [Kubernetes service statuses](#kubernetes-service-statuses)
        - [External IP Management](#external-ip-management)
      - [Viewing Logs](#viewing-logs)
      - [Metrics](#metrics)
    - [Pointing a domain at your deployment](#pointing-a-domain-at-your-deployment)
    - [Securing your deployment](#securing-your-deployment)
    - [Deleting your deployment](#deleting-your-deployment)
    - [Multiple Deployments](#multiple-deployments)
      - [Rellm Ingress: sharing one LoadBalancer across many domains (recommended)](#rellm-ingress-sharing-one-loadbalancer-across-many-domains-recommended)
      - [Central Storage: sharing Postgres/object storage across many namespaces](#central-storage-sharing-postgresobject-storage-across-many-namespaces)
      - [Example Kubernetes Cluster Setups](#example-kubernetes-cluster-setups)
        - [K8s cluster with multiple Kubernetes LoadBalancers (without a shared ingress)](#k8s-cluster-with-multiple-kubernetes-loadbalancers-without-a-shared-ingress)
        - [K8s cluster with multiple Rellm servers/deployments behind a single shared LoadBalancer](#k8s-cluster-with-multiple-rellm-serversdeployments-behind-a-single-shared-loadbalancer)
    - [Maximally-Efficient Configuration](#maximally-efficient-configuration)
      - [One-time cluster setup](#one-time-cluster-setup)
      - [Adding a site](#adding-a-site)
      - [Day-to-day](#day-to-day)
    - [Upgrading your deployed PostgreSQL](#upgrading-your-deployed-postgresql)
    - [Rolling out manifest changes](#rolling-out-manifest-changes)
    - [Environment Variables](#environment-variables)
  - [Rellm Deploys Development](#rellm-deploys-development)
    - [How `make` relates to `rellm deploy`](#how-make-relates-to-rellm-deploy)
    - [What the `rellm` launcher scripts (`rellm_homebrew.sh` and `rellm_linux.sh`) do](#what-the-rellm-launcher-scripts-rellm_homebrewsh-and-rellm_linuxsh-do)
    - [The guidelines above, with `make -C deploys ...`](#the-guidelines-above-with-make--c-deploys-)
    - [Tests](#tests)
    - [Adding or changing a target](#adding-or-changing-a-target)
    - [Credentials rule](#credentials-rule)
    - [Deploy scripts](#deploy-scripts)

This document has two parts. [End-User Deployment](#end-user-deployment) is for people deploying Rellm to their own Kubernetes cluster, and describes every command as a `rellm deploy ...` command (from the Homebrew or Linux package). [Rellm Deploys Development](#rellm-deploys-development) is for contributors: how `make` underlies `rellm deploy`, what the launcher scripts do, and the same guidelines again in `make -C deploys ...` syntax.

## End-User Deployment

Rather than requiring Helm, Ansible, Terraform, or other orchestration layers, Rellm deployment takes a more primitive route. Rellm's Homebrew and Linux packages bundle a full copy of this `deploys/` directory, so you can simply use `rellm deploy` (which runs `make` for you - you need `make` installed, but you don't have to know how to use it) to deploy:

* Install the `rellm` package: [Homebrew](https://github.com/JonLatane/rellm#macos-install-and-run-via-homebrew) or [Linux](https://github.com/JonLatane/rellm#linux-self-updateable-tarbz2-with-arm64-and-amd64-binaries-and-launcher). (Or, see [Rellm Deploys Development](#rellm-deploys-development) to maintain one cloned Rellm repo per cluster whose deployments you want to manage and use `make` directly.)
* `rellm deploy create_backend_data create_internal_backend -n rellm` to create backing Postgres and object storage/S3 instances and your BE instance.
    * `-n <namespace>` (or `--namespace <namespace>`, just like `kubectl`) is required (no default) - this deploys Postgres, object storage and Rellm to whichever namespace you name, e.g. `rellm deploy create_backend_data create_internal_backend -n mynamespace`.
    * For "production-ready" performance you can (and should) skip the `create_backend_data` part and instead configure external, managed Postgres and/or object storage/S3 servers.

See [the Cert-Manager integration README](./generated_certs/README.md) for more info on generating certs. At a high level, for a K8s deploy, `generated_certs/Makefile` will simply generate Cert-Manager K8s YAML to `deploys/generated_certs/k8s/cert-manager.\[digitalocean\].\[my-domain.com\].generated.yaml`. Applying that YAML (also doable through `rellm deploy`) sets up K8s/Cert-Manager to auto-generate the certs for your Rellm instance in its namespace where it will look for them.

As a user or a contributor, it's helpful to understand that Rellm deployment is built upon:

* `make` and the `Makefile` targets in this `deploys/` directory and its subdirectories, which use/require:
  * `sed`
  * `jq`
  * `kubectl`
  * `openssl` (generating credentials)
  * `mc`, the MinIO Client (`brew install minio/stable/mc`) -- only for [central storage](./central_storage/README.md) provisioning/transitions
  * `tmux` -- only for `view_tmux_logs` (see [Viewing Logs](#viewing-logs))
* `Dockerfile`s in `deploys/docker`
  * As a user, these are really just for reference, as you'll likely be deploying pre-built images from [jonlatane/rellm](https://hub.docker.com/r/jonlatane/rellm).
* Kubernetes `.yml` files in `deploys/k8s` and `deploys/generated_certs/k8s` (for using Rellm's Cert-Manager integration)
  * `.template.yml` files are used to generate `.yml` files for managing your own deployment.

Virtually all deployment-related targets will involve `make` calling `kubectl` with either predefinied `.yml`, or after modifying `.template.yml` files.

Every `rellm deploy` argument is either a target (`create_backend_data`), a kubectl-style flag (`-n`/`--namespace`, `--domain`, `--confirm`, and `--tail`/`--lines` for logs), or a `VAR=value` setting (e.g. `SIZE=20Gi`). See [Environment Variables](#environment-variables) for the full list. `rellm help deploys` shows this document in your `$PAGER` (`less`, `more`, ...). Tab-completion is available for targets, for the flags above, and -- after `-n`/`--namespace` -- for the namespaces in your cluster (see the [main README](https://github.com/JonLatane/rellm#deploying-dockerhub-images-to-kubernetes-from-homebrewlinux-rellm-deploy)).

### Basic Deployment
By following these instructions, you will bring up one namespace as diagrammed here in your Kubernetes cluster:

[K8s cluster with multiple Kubernetes LoadBalancers](#k8s-cluster-with-multiple-kubernetes-loadbalancers)

If you have `kubectl` and `make`, you can be setup in a few minutes. (If you're looking for a quick, fairly priced, scalable Kubernetes host, [I recommend DigitalOcean](https://m.do.co/c/1eaa3f9e536c).) First make sure `kubectl` is setup correctly and your instance has the `rellm` namespace available with `kubectl get services` and `kubectl get namespace rellm`:

```bash
$ kubectl get services
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.245.0.1   <none>        443/TCP   161d
$ kubectl get namespace rellm
Error from server (NotFound): namespaces "rellm" not found
```

To begin setup, first install `rellm` (see the [main README](https://github.com/JonLatane/rellm#packages-images--deployments)), then check that it works:

```bash
rellm version
```

Next, to create Postgres, object storage and two load-balanced Rellm servers in the namespace `rellm` (plus a few recurring jobs), run:

```bash
# THIS STEP WILL COST MONEY WITH MOST KUBERNETES PROVIDERS. ($12/mo. at DigitalOcean)
# The create_external_backend target, specifically, will create the Joline service as a K8s LoadBalancer.
# Of course, it costs nothing to use Minikube.
# To deploy for use with a different ingress (say, a shared nginx, or Rellm's pending internal LB), use create_internal_backend or deploy_be_internal_insecure_create to deploy it as a K8s ClusterIP instead.
# -n/--namespace is required (no default) - pick whichever namespace you want this deployed to.
rellm deploy create_backend_data create_external_backend -n rellm
```

That's it! You've created object storage and Postgres servers (with randomly generated credentials -- see [Credentials](#credentials)) along with a Rellm instance that *doesn't have TLS yet*, so ***passwords and auth tokens will be sent in plain text*** (You should secure it immediately if you care about any data/people, but feel free to play around with it until you do! Simply `rellm deploy delete_backend_data create_backend_data restart_backend -n rellm` to reset your server's data.) Because Rellm is a very tiny Rust service, it will all be up within seconds. Your Kubenetes provider will probably take some time to assign you an IP, though.

#### Deploying to namespaces other than `rellm`
`-n <namespace>` (or `--namespace <namespace>`) is required (no default) for every namespace-specific `rellm deploy` target, so you always pick the namespace explicitly: `rellm deploy create_backend_data create_external_backend -n my_namespace` to deploy to `my_namespace`. This should work for any of the `deploy_*` targets in Rellm. (`NAMESPACE=my_namespace` works in place of `-n my_namespace`, too, as an argument or an environment variable.) Targets that act on the whole cluster rather than one namespace (like `create_ingress` or `create_central_storage`) take no namespace.

#### Credentials
**No credential is ever checked into this repo, hand-typed, or reused between deployments -- every one is generated, randomly, by a target or script here.**

* **Per-namespace deploys** (`create_backend_data`, and the `create_*_backend` targets, which run it first): `create_backend_data_credentials` generates a random Postgres password and object storage credentials into a `rellm-data-credentials` Secret in the namespace. The Postgres/object storage manifests and the server manifests all read it via `secretKeyRef`; the dump/restore targets (`dump_backend_postgres`, ...) read the password from the same Secret (or take `PG_PASSWORD=...`). It **never regenerates an existing Secret**: Postgres and the object storage server only read their credentials when initializing an empty volume, so a "new" value would silently stop matching the real one.
* **[Central storage](./central_storage/README.md)**: the shared instances' own admin credentials are random Secrets in `rellm-storage`, and every namespace on them gets its own Postgres role and object storage user -- named after the namespace, random passwords, each restricted to only that namespace's database/bucket -- in a `rellm-central-data` Secret.
* **Getting them back out:** `rellm deploy get_all_storage_credentials` prints every one of those Secrets, decoded, across all namespaces (no namespace needed). Run it and put the output in a password manager -- these Secrets are the only copy. In particular, deleting a namespace (`kubectl delete namespace`) deletes its Secret while the data volumes survive (`reclaimPolicy: Retain`), and without the saved password you can't get back into that Postgres data.
* **Namespaces deployed before this existed** have their credentials inline in the running Deployments/StatefulSets. Run `deploys/data_migrations/adopt_legacy_data_credentials.sh <namespace>` once per namespace *before its next manifest rollout* (`rellm deploy update_*`; see [Rolling out manifest changes](#rolling-out-manifest-changes)) -- it creates the Secret from the namespace's live values (verifying they all agree; nothing is restarted or changed) so the new manifests keep working against the same data. CI's image-only deploys don't need it. Those inline values were the old checked-in defaults, so treat them as compromised: the real fix is moving the namespace to central storage ([`transition_jonline_namespace_to_central_storage.sh`](./central_storage/README.md#transitioning-an-existing-namespace)), which issues fresh random credentials.
* **Rotating** a credential means changing it in the running server *and* the Secret (Postgres: `ALTER ROLE ... PASSWORD`; object storage: the server's root credentials env / `mc admin user`), then restarting the consumers. There's no target for it yet -- and never delete a `rellm-*credentials` Secret while its data volume lives on.

### Validating your deployment
#### Kubernetes service statuses
To see *everything* you just deployed (object storage, postgres, Rellm server and background cron jobs), run `rellm deploy get_backend_all -n rellm`. It should look something like this (with fewer old ReplicaSets after a fresh install, probably):

```bash
$ rellm deploy get_backend_all -n rellm
kubectl get all -n rellm
NAME                                           READY   STATUS    RESTARTS   AGE
pod/rellm-7f69759bd7-x64nd                     1/1     Running   0          30s
pod/rellm-7f69759bd7-x6scq                     1/1     Running   0          36s
pod/rellm-jobs-5d8c9b7f64-k2m9q                1/1     Running   0          36s
pod/rellm-object-storage-0                     1/1     Running   0          4d22h
pod/rellm-postgres-0                           1/1     Running   0          53m
pod/rellm-preview-generator-6b7d8f5c9-tq4wz    1/1     Running   0          36s

NAME                           TYPE           CLUSTER-IP       EXTERNAL-IP       PORT(S)                                                     AGE
service/rellm                  LoadBalancer   10.245.199.164   178.128.137.194   27707:30679/TCP,443:32401/TCP,80:30932/TCP,8000:30414/TCP   20d
service/rellm-object-storage   ClusterIP      None             <none>            9000/TCP                                                    4d22h
service/rellm-postgres         ClusterIP      None             <none>            5432/TCP                                                    53m

NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/rellm                      2/2     2            2           20d
deployment.apps/rellm-jobs                 1/1     1            1           20d
deployment.apps/rellm-preview-generator    1/1     1            1           20d

NAME                                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/rellm-54d8b475bb                      0         0         0       4d6h
replicaset.apps/rellm-7f69759bd7                      2         2         2       38s
replicaset.apps/rellm-jobs-5d8c9b7f64                 1         1         1       38s
replicaset.apps/rellm-preview-generator-6b7d8f5c9     1         1         1       38s

NAME                                    READY   AGE
statefulset.apps/rellm-object-storage   1/1     4d22h
statefulset.apps/rellm-postgres         1/1     53m
```

##### External IP Management
Use `rellm deploy get_backend_external_ip -n rellm` to see what your service's external IP is (until set, it will return `<pending>`).

```bash
$ rellm deploy get_backend_external_ip -n rellm
188.166.203.133
```

Finally, once the IP is set, to test the service from your own computer, use `rellm deploy deploy_test_be_unsecured -n rellm` to run tests against that external IP (you need `grpcurl` for this; `brew install grpcurl` works for macOS):

```bash
$ rellm deploy deploy_test_be_unsecured -n rellm
Getting services on target server...
grpcurl -plaintext 188.166.203.133:27707 list
grpc.reflection.v1alpha.ServerReflection
rellm.Rellm

Getting Rellm service version...
grpcurl -plaintext 188.166.203.133:27707 rellm.Rellm/GetServiceVersion
{
  "version": "0.1.18"
}

Getting available Rellm RPCs...
grpcurl -plaintext 188.166.203.133:27707 list rellm.Rellm
rellm.Rellm.CreateAccount
rellm.Rellm.GetCurrentUser
rellm.Rellm.GetServiceVersion
rellm.Rellm.Login
rellm.Rellm.AccessToken
```

That's it! You're up and running, although again, *it's an unsecured instance* where ***passwords and auth tokens will be sent in plain text***. Get that thing secured before you go telling people to use it!

#### Viewing Logs
Four targets (all built on plain `kubectl`; no `kail` needed) show a namespace's logs. All take `-n <ns>`/`--namespace <ns>`:

```bash
rellm deploy view_server_logs -n jonline            # Print the server's logs and return
rellm deploy view_job_logs -n jonline --tail        # Tail (follow) the background jobs' logs
rellm deploy view_preview_generator_logs -n jonline # The preview generator's logs
rellm deploy view_tmux_logs -n jonline              # tmux session: Server | Jobs | Preview Generator
```

* `view_server_logs` reads the `rellm` Deployment, which runs several replicas, and merges them into one stream; each line is prefixed `[pod/<pod name>/rellm]` so you can tell the replicas apart. Printed (not following), the replicas' lines are merged by timestamp. `view_job_logs` reads `rellm-jobs` (the one pod running [`background_jobs.sh`](../backend/background_jobs.sh); every line is labeled with its job), and `view_preview_generator_logs` reads `rellm-preview-generator`.
* **`--tail`** follows the logs, like `tail -f`, until you press Ctrl-C. Without it, the logs are printed and the command returns. When following, it reconnects if the pods are replaced (a rollout, say). **`--lines <n>`** limits each pod to its last `<n>` lines; the default is everything Kubernetes still has, or the last 50 lines per pod when following.
* **`view_tmux_logs`** opens a [tmux](https://github.com/tmux/tmux) session named `rellm-logs-<namespace>` with Server on the left, Jobs in the middle and Preview Generator on the right, each following its logs (with the mouse enabled: click a pane to focus it, drag a border to resize). It skips the Preview Generator pane when no preview generator pod is running. It tails implicitly, so it ignores `--tail` (without failing over it) and says so at startup. Run inside tmux, it switches your client to that session instead of nesting one. Needs `tmux` installed.
* In `rellm deploy`, `-n` means `--namespace`, as in `kubectl`, not `make`'s `-n`; spell make's dry run `--dry-run`.

#### Metrics
If you want metrics available for your Rellm cluster (so `kubectl top pods -n rellm` and `kubectl top nodes` work, for instance), install Kubernetes' [metrics-server](https://github.com/kubernetes-sigs/metrics-server) once per cluster (some Kubernetes providers already include it):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Pointing a domain at your deployment
Before you can secure with LetsEncrypt, you need to point a domain at your Rellm instance's IP. Again, you can get the IP with `rellm deploy get_backend_external_ip -n rellm`, and create your DNS records with your DNS provider. If you're choosing a DNS provider, it's worth noting that [I recommend DigitalOcean DNS (sponsored link)](https://m.do.co/c/1eaa3f9e536c) and Rellm has scripts for it. However, any [Cert-Manager](http://cert-manager.io) supported DNS provider (for the LetsEncrypt dns01 challenge) should be pretty easy to set up.

Continue to the next section for more info about setting up encryption and its relation to your DNS provider.

### Securing your deployment
Rellm uses 🐕💩EZ, boring normal TLS certificate management to negotiate trust around its decentralized social network. If you're using DigitalOcean DNS you can be setup in a few minutes.

See [`deploys/generated_certs/README.md`](https://github.com/JonLatane/rellm/tree/main/deploys/generated_certs) for quick TLS setup instructions, either [using Cert-Manager (recommended)](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/README.md#use-cert-manager-recommended), [some other CA](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/README.md#use-certs-from-another-ca) or [your own custom CA](https://github.com/JonLatane/rellm/blob/main/generated_certs/README.md#use-your-own-custom-ca) (i.e. to distribute a secure, network-specific Flutter app and only let users in through that - custom CAs would break/disable the web app entirely).

See [`backend/README.md`](https://github.com/JonLatane/rellm/blob/main/backend/README.md) for more detailed descriptions of how the deployment and TLS system works.

### Deleting your deployment
You can delete your Rellm deployment piece by piece with `rellm deploy delete_backend delete_backend_postgres -n my_namespace` or simply `kubectl delete namespace my_namespace`. Before deleting a namespace's storage, save its credentials (`rellm deploy get_all_storage_credentials` -- see [Credentials](#credentials)).

Once a namespace has been moved to central storage and you've verified it, `rellm deploy delete_backend_data_pvcs -n my_namespace --confirm my_namespace` removes its old per-namespace Postgres/object storage and their PVCs (it refuses unless the namespace really is on central storage, and keeps the underlying volumes as `Released` PVs until you delete them yourself).


### Multiple Deployments
As mentioned in [Deploying to namespaces other than `rellm`](#deploying-to-namespaces-other-than-rellm): to deploy anything to a namespace other than `rellm`, simply add `-n my_namespace`. So, for the initial deploy, `rellm deploy create_backend_data create_external_backend -n my_namespace` to deploy to `my_namespace`. This should work for any of the `deploy_*` targets in Rellm.

Note that multiple *external* deployments will each have a Kubernetes LoadBalancer. On many providers, this is relatively expensive (an external IP, $12/mo on DigitalOcean). Other targets include `create_internal_backend` and `deploy_be_internal_insecure_create` (the latter of which will specifically ignore K8s-stored TLS certificates, to save CPU time by not encrypting interal services).

#### Rellm Ingress: sharing one LoadBalancer across many domains (recommended)
[`deploys/ingress/`](./ingress/README.md) sets up a single, shared [Traefik](https://traefik.io) ingress that lets any number of Rellm instances - each still in its own namespace, each with its own domain, Postgres, object storage and Cert-Manager certs - share **one** external IP/LoadBalancer instead of one each. Each backend keeps terminating its own TLS exactly as it does today (`create_internal_backend`/`update_internal_backend`); the ingress only reads the plaintext SNI hostname from the TLS handshake to route the still-encrypted bytes to the right namespace, so no certs need to move, be duplicated, or change hands.

```bash
# Once per cluster:
rellm deploy create_ingress
# Once per domain, after that domain's own basic deployment already exists:
rellm deploy add_ingress_domain -n my_namespace --domain my.domain.example.com
```

See [`deploys/ingress/README.md`](./ingress/README.md) for the full walkthrough, including how to cut a domain over from its own LoadBalancer without downtime.

#### Central Storage: sharing Postgres/object storage across many namespaces
Each namespace's Postgres and object storage above is its own StatefulSet - 2 PVCs per namespace. Most managed Kubernetes offerings cap how many PVCs a cluster can attach at all (DigitalOcean's DOKS: 15), so that runs out fast once you're hosting more than a handful of domains, regardless of how cheap or expensive each individual domain's traffic is. [`deploys/central_storage/`](./central_storage/README.md) sets up one shared Postgres + object storage instance (2 PVCs, full stop) that any number of *new* namespaces can point at instead, each with its own database and bucket (named after the namespace) inside the shared instance rather than an instance of its own.

```bash
# Once per cluster:
rellm deploy create_central_storage
# Once per new namespace, instead of create_backend_data create_internal_backend:
rellm deploy create_backend_central_data create_internal_central_data_backend -n my_namespace
```

This creates no shared credentials anyone has to know: the shared instances' admin credentials are random Secrets, and each namespace gets its own restricted Postgres role/object storage user (see [Credentials](#credentials)). Existing per-namespace deployments are untouched until you move them with `rellm deploy transition_backend_to_central_data -n my_namespace` (site is down for the duration; the old storage is left running for you to verify and later remove with `delete_backend_data_pvcs`). Known gap: `dump_backend_postgres`/`restore_backend_postgres`/`upgrade_backend_postgres` only work on a namespace's own Postgres -- central storage has PVC size/resize targets (`get_central_*_pvc_size`, `resize_central_*_pvc`) but no backup or upgrade path yet. See [`deploys/central_storage/README.md`](./central_storage/README.md) for the full walkthrough.

#### Example Kubernetes Cluster Setups
##### K8s cluster with multiple Kubernetes LoadBalancers (without a shared ingress)
This is how Rellm was originally deployed, and still is by default for a single domain.

![K8s cluster with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Kubernetes_Deployment.svg)

##### K8s cluster with multiple Rellm servers/deployments behind a single shared LoadBalancer
This is what [`deploys/ingress/`](./ingress/README.md) sets up.
![System with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg)

### Maximally-Efficient Configuration
This is how the Rellm author's own cluster runs, and the setup to use if you want to host *many* sites cheaply: **one** LoadBalancer, **one** mail server and **one** Postgres/object storage pair shared by every site, so each additional site costs little more than its own pods.

| Shared piece | Namespace | What it replaces (per site) | Docs |
|---|---|---|---|
| **Traefik** - one `LoadBalancer`/external IP routing every domain by SNI/`Host`, plus plain TCP `:25` for mail | `traefik-ingress` | a `LoadBalancer` per site (~$12/mo each) | [`ingress/`](./ingress/README.md) |
| **Stalwart** - one internet-facing SMTP server; hands each domain's mail to that site's `rellm` | `rellm-email` | a mail server per site | [`email/`](./email/README.md) |
| **Central storage** - one Postgres + one Silo (2 PVCs total); each site gets its own database/bucket and a role/user restricted to just that | `rellm-storage` | 2 PVCs per site (DOKS caps a cluster at 15) | [`central_storage/`](./central_storage/README.md) |

Each site is then just a namespace holding `rellm` (x2), `rellm-jobs`, `rellm-preview-generator`, its `rellm-tls` certificate Secret and its `rellm-central-data` credentials Secret. See the [diagram](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg). Sites deploy from CI by image tag only ([Rolling out manifest changes](#rolling-out-manifest-changes)).

Commands below assume `kubectl` points at the right cluster (`kubectl config current-context`). They're all `rellm deploy` commands: one-time setup needs no `-n`, and per-site steps take `-n <the site's namespace>`.

#### One-time cluster setup
Do these once per cluster, in this order.

1. **Central storage** (needs `openssl` locally; the commands in [Adding a site](#adding-a-site) also need `mc`, `brew install minio/stable/mc`). Generates random admin credentials into Secrets in `rellm-storage` and creates the shared Postgres and Silo:

   ```bash
   rellm deploy create_central_storage
   rellm deploy wait_central_postgres_ready wait_central_object_storage_ready
   ```

   Defaults are 10Gi (Postgres) / 20Gi (Silo); grow them later with `rellm deploy resize_central_postgres_pvc SIZE=...` and `rellm deploy resize_central_object_storage_pvc SIZE=...` (grow-only).
2. **Traefik ingress** - the single shared LoadBalancer:

   ```bash
   rellm deploy create_ingress
   rellm deploy get_ingress_external_ip      # the one IP every domain's A record points at
   ```
3. **Cert-Manager** - issues each site's Let's Encrypt certificate (installed once; each site's DigitalOcean credential is created per site below):

   ```bash
   rellm deploy deploy_certmanager
   ```
4. **Stalwart** (shared mail server). It sits *behind* the Traefik you just installed (port 25 enters through Traefik's `smtp` entrypoint), so do this after step 2.
   1. Pre-set Stalwart's admin password. Choose your own - there is deliberately no default, and `add_email_domain` below authenticates with it:

      ```bash
      rellm deploy create_email_admin_secret ADMIN_PASSWORD='<a long random password>'
      ```
      This must happen **before** `create_email`: Stalwart only reads it on a completely empty data volume.
   2. Install it:

      ```bash
      rellm deploy create_email
      ```
   3. Open its admin UI / setup wizard (`ClusterIP`-only, never exposed publicly) and log in as `admin` with that password:

      ```bash
      rellm deploy deploy_email_admin_port_forward     # then open http://localhost:8080
      ```
      On a fresh volume Stalwart boots into the wizard. Choose **RocksDB** for storage (its PVC holds only Stalwart's own config and queue - never user mailboxes) and send logging to the **console** so `kubectl logs -n rellm-email deployment/stalwart` shows something. Stop the port-forward when done.
   4. Confirm your provider lets inbound traffic reach port 25 (some block it by default and need a ticket), and that the Traefik LoadBalancer forwards TCP `:25`. `rellm deploy deploy_email_get_ip` prints the IP your MX records resolve to - it's the same ingress IP.
   5. Smoke test, bypassing DNS: `openssl s_client -connect <ingress-ip>:25 -crlf` should show Stalwart's `220 ... ESMTP` banner. Full details and troubleshooting: [`email/README.md`](./email/README.md).

#### Adding a site
Per site (shown for namespace `my-site` and domain `my-site.example.com`; the namespace name becomes its database, bucket and credentials' name, so use lowercase letters, digits and `-`, at least 3 characters).

**DNS first.** Point an `A` record for `my-site.example.com` at the ingress IP (`rellm deploy get_ingress_external_ip`). Certificates use DNS-01 through DigitalOcean (for the apex and `*.my-site.example.com`), so `my-site.example.com` must be a DigitalOcean DNS zone - delegate it with `NS` records from wherever the parent domain lives - and the API token you give Cert-Manager needs write access to it.

1. **Provision the site's slice of central storage** - database + role, bucket + user, and a `rellm-central-data` Secret with fresh random credentials, each restricted to only this site's data (also creates the namespace):

   ```bash
   rellm deploy create_backend_central_data -n my-site
   ```
2. **Deploy the backend** (reads that Secret):

   ```bash
   rellm deploy create_internal_central_data_backend -n my-site
   ```
3. **TLS.** Prompts for the provider (press Enter for `digitalocean`), your DigitalOcean API token (hidden), the domain and an admin email. The certificate can take a few minutes; the pods read it at startup, so restart them once it's `READY`:

   ```bash
   rellm deploy deploy_certmanager_credential -n my-site
   kubectl get certificate -n my-site -w     # wait for READY=True
   rellm deploy restart_backend -n my-site
   ```
4. **Route the domain through Traefik:**

   ```bash
   rellm deploy add_ingress_domain -n my-site --domain my-site.example.com
   ```

   Verify with `curl -I https://my-site.example.com` and `grpcurl my-site.example.com:27707 list`. If the site 404s or hangs right after, bounce Traefik (`rellm deploy deploy_ingress_restart`, or `kubectl rollout restart deployment traefik -n traefik-ingress`) - it briefly interrupts every domain, so only if needed.
5. **Email (optional)** - Stalwart must already be set up (above) and step 2 deployed, since the mail hook calls this namespace's `rellm` on port 27705:

   ```bash
   rellm deploy add_email_domain -n my-site --domain my-site.example.com
   rellm deploy list_email_domains          # confirm it's listed
   ```

   Then add these records in the DNS zone:

   | Type | Name | Value |
   |---|---|---|
   | `MX` | `@` | `my-site.example.com.` priority `10` (the `A` record sends it to Traefik; any name resolving to the ingress IP works) |
   | `TXT` | `@` | `v=spf1 mx ~all` |
   | `TXT` | `_dmarc` | `v=DMARC1; p=none; rua=mailto:you@example.com` |

   Mail is receive-only. Test before relying on DNS - create a real user on the site first (mail to an unknown username is accepted, then silently dropped), then:

   ```bash
   swaks --to <username>@my-site.example.com --server "$(rellm deploy get_ingress_external_ip)" --header "Subject: Test" --body "Test message."
   kubectl logs -f deployment/stalwart -n rellm-email      # accepted, hook fired?
   rellm deploy view_server_logs -n my-site --tail         # POST /email arrived?
   ```

   `550 5.1.2 Relay not allowed` with the domain listed means Stalwart cached an earlier "no such domain": `rellm deploy deploy_email_restart`, then retry.
6. **Save the credentials** - these Secrets are the only copy: `rellm deploy get_all_storage_credentials`.
7. **Keep it current in CI.** CI only bumps image tags on namespaces it knows about, so add a deploy job for the new namespace in `.github/workflows/server_ci_cd.yml` (copy an existing one, such as `deploy_rellm_org`). Until then the site runs the image from step 2 (the manifests' base version).

#### Day-to-day
- **Deploys:** push to `main`; CI bumps each site's image tags. Manifest changes are rolled out deliberately - see [Rolling out manifest changes](#rolling-out-manifest-changes).
- **Capacity:** `rellm deploy get_central_postgres_pvc_size get_central_object_storage_pvc_size`, and grow with the `resize_central_*_pvc` targets. The central Postgres and Silo are shared by every site and have no backup or upgrade path yet (see [Central Storage](#central-storage-sharing-postgresobject-storage-across-many-namespaces)).
- **Retiring a site:** delete its namespace, then `rellm deploy delete_backend_central_data -n my-site --confirm my-site` to permanently remove its database, bucket and credentials. `rellm deploy remove_ingress_domain -n my-site --domain my-site.example.com` and `rellm deploy remove_email_domain -n my-site --domain my-site.example.com` take it out of Traefik and Stalwart.

### Upgrading your deployed PostgreSQL
_(This section covers a namespace's own Postgres. [Central storage](./central_storage/README.md)'s shared Postgres has no dump/upgrade targets yet.)_

The Postgres image tag lives in `k8s/k8s-postgres-$(K8S_PROVIDER).yaml`. For a **minor** version bump (e.g. `17.5` → `17.6`), just edit the tag and run `rellm deploy update_backend_postgres -n rellm`. For a **major** version bump (e.g. `14` → `17`), the on-disk data format changes, so don't just `update_backend_postgres` - use:

```bash
rellm deploy upgrade_backend_postgres -n my_namespace
```

This handles the whole migration: it dumps your current database (via a temporary port-forward, no `kubectl exec` needed), stops the app and the old Postgres, brings up the new version (initdb'd fresh on a new PVC subPath, so the old data directory is never touched), restores the dump into it, then restarts the app. Your old version's data stays on disk as an instant rollback until you're confident in the new one, at which point `rellm deploy delete_backend_postgres_old_data -n my_namespace` permanently deletes it.

### Rolling out manifest changes
CI deploys are **image-only**: `.github/workflows/server_ci_cd.yml` runs `kubectl set image` for each namespace's `rellm`, `rellm-jobs` and `rellm-preview-generator` Deployments and never applies a manifest. That makes a CI deploy independent of how a namespace is configured (central or own storage) and safe during a storage transition -- it can't change replicas, env, credentials or wiring, so a site you've scaled down for a cutover stays down. The cost: **changes under `deploys/k8s/` (a new env var, port, Service entry, replica count, a new Deployment...) are not rolled out by CI** -- the new image runs against the old manifests until you roll them out. The `manifest_change_notice` CI job warns on any push that touches those files. To roll out, per namespace:

```bash
rellm deploy update_internal_central_data_backend -n my_namespace
```

This regenerates that namespace's manifests from the templates and applies them, **keeping whatever images the Deployments are running** (CI's `<version>-<sha>` tags) rather than resetting them to the manifests' base version (`REPO_IMAGES=1` to deploy the manifests' tags as written). Do it for every namespace, and do it *before* (or together with) deploying code that needs the new config. A brand-new namespace has no Deployments for CI to update: create it with `rellm deploy create_backend_central_data create_internal_central_data_backend -n my_namespace`, then CI keeps its image current.

### Environment Variables
Settings other than the namespace are `VAR=value` arguments to `rellm deploy` (e.g. `rellm deploy resize_central_postgres_pvc SIZE=20Gi`), or plain environment variables (`SIZE=20Gi rellm deploy resize_central_postgres_pvc`) -- including anything you `export` in your shell or set in `~/.rellm`. Prefer the flags in your commands: `-n`/`--namespace` over `NAMESPACE`, `--domain` over `DOMAIN` and `--confirm` over `CONFIRM`. Everything else has no flag equivalent, and mostly only matters for the one target noted.

| Variable | Used by | Default | Meaning |
|---|---|---|---|
| `NAMESPACE` | nearly every target | none (required) | The namespace to act on; what `-n`/`--namespace` sets. Must be a valid Kubernetes namespace name (lowercase letters, digits and `-`). Cluster-wide targets (`create_ingress`, `create_central_storage`, `deploy_certmanager`, ...) and `get_all_storage_credentials` and `copy_server_*_configuration` don't need it |
| `STORAGE_NAMESPACE` | central storage targets | `rellm-storage` | Where the shared Postgres/object storage lives |
| `K8S_PROVIDER` | Postgres/object storage/StorageClass targets | `digitalocean` | Picks which `k8s/*-<provider>.yaml` manifests to use |
| `DOMAIN` | `add_ingress_domain`, `remove_ingress_domain`, `add_email_domain`, `remove_email_domain` | none (required) | The site's public hostname; what `--domain <domain>` sets |
| `EXTRA_DOMAINS` | `add_ingress_domain` | empty | Space-separated extra hostnames fronting the same backend (e.g. a CDN proxy) |
| `CONFIRM` | `delete_backend_data_pvcs`, `delete_backend_central_data` | none (required) | Must equal the namespace -- confirms a destructive, permanent delete; what `--confirm <namespace>` sets |
| `REPO_IMAGES` | `update_internal_central_data_backend` | unset | Set to `1` to deploy the manifests' image tags instead of keeping the images currently running |
| `BACKEND_REPLICAS` | `start_backend` | `2` | Replicas restored after a `stop_backend` maintenance window |
| `SIZE` | `resize_*_pvc` targets | none (required) | New PVC size, e.g. `20Gi` (grow-only) |
| `PG_PASSWORD` | Postgres dump/restore/upgrade targets | read from the namespace's `rellm-data-credentials` Secret | Override the Postgres password |
| `PG_BACKUP_DIR` | Postgres dump/restore/upgrade targets | `backups` | Where dumps are written/read |
| `PG_UPGRADE_LOCAL_PORT` | Postgres dump/restore/upgrade targets | `15432` | Local port for the temporary port-forward |
| `TEST_GRPC_TARGET` | `deploy_test_be*` | `<the backend's external IP>:27707` | What the smoke tests connect to |
| `ADMIN_USER`, `ADMIN_PASSWORD` | `create_email_admin_secret` and the `*_email_domain` targets | `admin`; none (required) | Stalwart's admin credentials |
| `STALWART_ADMIN_URL` | the `*_email_domain` targets | `http://localhost:8080/jmap` | Stalwart's Management API |
| `INGRESS_NAMESPACE`, `TRAEFIK_VERSION` | ingress targets | `traefik-ingress`; pinned in `ingress/Makefile` | Where the shared Traefik runs, and its version |
| `SOURCE`, `TARGET`, `COLUMN` | `copy_server_configuration` (and `copy_server_cluster_configuration`/`copy_server_vapid_configuration`, which don't take `COLUMN`) | none (required) | Namespaces to copy a `server_configurations` column between, and which column |
| `--tail`, `--lines <n>` | `view_*_logs` | | Not variables, but flags (`LOG_TAIL=1`, `LOG_LINES=<n>` in `make` terms) -- see [Viewing Logs](#viewing-logs) |

## Rellm Deploys Development

### How `make` relates to `rellm deploy`
Everything above is `make`. `deploys/Makefile` is the single source of truth for every target, and `rellm deploy <args>` is, in the Homebrew and Linux packages, just `make -C <the bundled copy of deploys/> <args>` (after the flag translation below). A target that works in one works in the other, and `make -C deploys <target> ...` from a clone of this repo is the same thing a package user runs. (`cd deploys && make <target> ...` is equivalent; the root `Makefile` also has passthroughs to many of the same targets.)

* **Subdirectory Makefiles are reached through passthroughs.** `ingress/`, `email/`, `central_storage/` and `generated_certs/` have their own Makefiles, but `rellm deploy` only ever runs `make -C deploys`, so each target there that users should run needs a one-line passthrough in `deploys/Makefile` (`$(MAKE) -C ingress <target>`).
* **`NAMESPACE` is required, with exceptions.** `deploys/Makefile` refuses to run without `NAMESPACE` (and validates it as a Kubernetes namespace name, since it ends up in `kubectl -n`, generated YAML, `sed` replacements and SQL identifiers). The targets in `NAMESPACE_FREE_TARGETS` at the top of that Makefile -- cluster-wide ingress/email/central storage/Cert-Manager targets, `get_all_storage_credentials`, `copy_server_*_configuration` -- skip that check because they don't act on a single namespace. A new cluster-wide target must be added to that list, or `rellm deploy <target>` will demand a `-n` it has no use for.
* **Variables.** `make` takes `VAR=value` arguments and environment variables interchangeably (`make -C deploys delete_backend_data_pvcs NAMESPACE=x CONFIRM=x` or `NAMESPACE=x CONFIRM=x make -C deploys delete_backend_data_pvcs`); `rellm deploy` forwards both. The [Environment Variables](#environment-variables) table lists them; give new ones an entry there.
* **Flags are only translated by `rellm deploy`.** To `make`, `-n` means `--dry-run`, and `--domain`, `--confirm`, `--tail` and `--lines` don't exist. The Homebrew/Linux launchers translate `-n <ns>`/`--namespace <ns>` (and `-n<ns>`, `-n=<ns>`, `--namespace=<ns>`) to `NAMESPACE=<ns>`, `--domain <domain>` (and `--domain=<domain>`) to `DOMAIN=<domain>`, `--confirm <value>` (and `--confirm=<value>`) to `CONFIRM=<value>`, `--tail` to `LOG_TAIL=1` and `--lines <n>` to `LOG_LINES=<n>` -- so in `make` you spell them the long way. (And in `rellm deploy`, spell make's dry run `--dry-run`.)
* Targets that generate files (e.g. `k8s/*.generated.yaml`, `ingress/k8s/rellm-routes.<namespace>.generated.yaml`) write them relative to the `deploys/` directory `make` runs in -- for a package, the bundled copy.

### What the `rellm` launcher scripts (`rellm_homebrew.sh` and `rellm_linux.sh`) do
[`docs/rellm_homebrew.sh`](../docs/rellm_homebrew.sh) and [`docs/rellm_linux.sh`](../docs/rellm_linux.sh) are the source of truth for the `rellm` command shipped in the Homebrew formula (CI splices the former into `Formula/rellm.rb`) and the Linux tarball (the latter is its `bin/rellm`), respectively -- edit these, never a generated copy. Both do the same things for deployment:

* **Bundle `deploys/`.** CI's `create_homebrew_release`/`create_linux_release` jobs `cp -R deploys/.` into the package's `opt/deploys` (tracked files only -- no generated certs, backups, etc.), next to the Rellm binaries. Homebrew's launcher knows that path at install time; the Linux launcher works it out at runtime from wherever the tarball was extracted.
* **`rellm deploy <args...>`** sources [`distributables.sh`](./distributables.sh) -- the implementation both launchers share -- and calls its `_rellm_deploys_run`, which checks that `make` is installed, translates the kubectl-style flags described above, and runs `make -C <opt/deploys> <args>`.
* **Tab-completion** for `rellm deploy <TAB>` calls `rellm --list-deploy-targets` (`_rellm_deploys_list_targets` in `distributables.sh`), which asks `make` itself to dump the Makefile's targets rather than parsing it. New targets are completed automatically; nothing to register. After `-n`/`--namespace` it calls `rellm --list-namespaces` (`_rellm_deploys_list_namespaces`: `kubectl get namespaces` with a short timeout, empty on any failure), and a leading `-` completes the flags `distributables.sh` translates -- so a new flag needs adding to the completion scripts in both launchers as well. `rellm help <TAB>` completes `deploys`.
* **`rellm help deploys`** calls `_rellm_deploys_help` in `distributables.sh`: it shows `deploys/README.md` (the copy bundled in the package) in `$PAGER`, falling back to `less`, then `more`, and just prints it when stdout isn't a terminal. Plain `rellm help` says this is a local copy of the GitHub page for the package's release (`https://github.com/JonLatane/rellm/blob/v<release>/deploys/README.md`, where `<release>` is what `rellm-server --version` prints, e.g. `0.5.553-20261005123456-abc1234`), or of the `main` branch if it can't run the server binary (e.g. running a launcher standalone from a clone).
* **Help text.** Each launcher has its own copy of the `rellm help` text (including the `Deployment` section and the log commands). Keep the two in sync with each other and with this document.

The launchers also run Rellm's own binaries, jobs and local dev dependencies (see their headers), which has nothing to do with `deploys/`. Both are plain `bash` that must keep working on macOS's stock bash 3.2 (hence, for instance, no `source <(...)` and care with empty arrays under `set -u`), and the Homebrew one is embedded in a Ruby heredoc, so it can't contain Ruby's string interpolation syntax (see its header).

[`kubernetes_logs.sh`](./kubernetes_logs.sh) is what the `view_*_logs` targets run (`bash ./kubernetes_logs.sh <server|jobs|preview_generator|tmux> --namespace <ns> [--tail] [--lines <n>]`; you can run it directly, too). It uses `kubectl logs -l app=<deployment> --prefix`, which already multiplexes pods into one stream, plus a merge-by-timestamp for non-follow mode, a reconnect loop for follow mode and the tmux layout for `tmux`.

### The guidelines above, with `make -C deploys ...`
For contributors working from a clone, the same commands as in [End-User Deployment](#end-user-deployment), by `make`:

```bash
# Deploy, per namespace (any target prefixed deploy_*, create_*, update_*, ... takes NAMESPACE):
make -C deploys create_backend_data create_external_backend NAMESPACE=rellm
make -C deploys get_backend_all NAMESPACE=rellm
make -C deploys get_backend_external_ip NAMESPACE=rellm

# Variables other than NAMESPACE are just more VAR=value arguments (or environment variables):
make -C deploys delete_backend_data_pvcs NAMESPACE=my_namespace CONFIRM=my_namespace
make -C deploys add_ingress_domain NAMESPACE=my_namespace DOMAIN=my.domain.example.com

# Cluster-wide targets take no NAMESPACE (they're in NAMESPACE_FREE_TARGETS):
make -C deploys create_central_storage
make -C deploys create_ingress
make -C deploys resize_central_postgres_pvc SIZE=40Gi

# Logs -- LOG_TAIL=1 is --tail (follow); LOG_LINES=<n> is --lines <n>:
make -C deploys view_server_logs NAMESPACE=jonline
make -C deploys view_job_logs NAMESPACE=jonline LOG_TAIL=1
make -C deploys view_tmux_logs NAMESPACE=jonline

# Same thing as the `rellm deploy` form -- these are equivalent:
rellm deploy view_job_logs -n jonline --tail
make -C deploys view_job_logs NAMESPACE=jonline LOG_TAIL=1
```

And the structure of this document's examples -- keep it when editing them: `-n`/`--namespace` rather than `NAMESPACE=` in `rellm deploy` examples; a `VAR=value` only where a target needs one (there is no flag for it); and every example a runnable `rellm deploy` command (so a target that a user is meant to run needs a `deploys/Makefile` passthrough, and a `NAMESPACE_FREE_TARGETS` entry if it's cluster-wide).

### Tests
`make -C deploys test` (or `make test_deploys` from the repo root) runs [`tests/`](./tests), a suite of plain-bash tests for everything on this page that can be checked without a cluster. CI runs it as the `test_deploys` job, and both the production deploy and the GitHub release wait for it. To run a few files: `bash deploys/tests/run.sh guard flags` (any `tests/<name>_tests.sh`).

* **No cluster, no side effects.** Each test file works in a temporary copy of `deploys/` (minus certs/keys, Postgres dumps and generated files), with stub `kubectl`, `tmux` and `pkill` first on `PATH` that record every call and return canned output. Tests assert on those calls, on make's output, and on the files recipes generate.
* **`make -n` alone isn't safe.** `make -n` (`--dry-run`) still *executes* any recipe line that mentions `$(MAKE)` -- so the passthroughs, and interactive targets like `deploy_certmanager_credential`, would run for real. Dry-run tests therefore use `make -n MAKE=true <target>` (`mk_dry` in [`tests/lib.sh`](./tests/lib.sh)), where a passthrough just shows up as `true -C ingress <target>`; everything else runs with stdin from `/dev/null`. Tests that need to see a recipe's real behavior (e.g. the routes `add_ingress_domain` generates) run make for real against the stub `kubectl` instead (`mk`).
* **What's covered:**
  * `guard_tests.sh`: every target requires a namespace unless it's in `NAMESPACE_FREE_TARGETS`; every `NAMESPACE_FREE_TARGETS` entry is a real target that runs without one; invalid `NAMESPACE`/`STORAGE_NAMESPACE` values are rejected.
  * `passthrough_tests.sh`: every target in `ingress/`, `email/`, `central_storage/` and `generated_certs/` is reachable through a `deploys/Makefile` passthrough (or deliberately listed as not, in that file), and no passthrough points at a missing target.
  * `flags_tests.sh`: `rellm deploy`'s `-n`/`--namespace`/`--tail`/`--lines` translation, under both `bash` and the system bash (3.2 on macOS).
  * `logs_tests.sh`: `kubernetes_logs.sh`, including timestamp merging, follow-mode reconnects and the tmux layout.
  * `ingress_tests.sh` and `email_tests.sh`: those targets' required variables, generated routes and `kubectl` calls, and that IP-printing targets output nothing but the IP.
  * `launchers_tests.sh`: both launchers, laid out like the real packages, end to end -- `rellm deploy`, `rellm help deploys` (including the pager), and the bash/zsh completions for targets, flags, namespaces and help topics.
  * `docs_tests.sh`: every `rellm deploy <target>` and `make -C deploys <target>` in this file and the main README is a real target; the launchers' `rellm help` mentions the log commands and flags; tab-completion lists the targets.
* **Adding a test:** a new `tests/<name>_tests.sh` that sources `lib.sh`, calls `sandbox_init` and `begin`, ends with `finish`, and uses the `check_*` helpers is picked up automatically. Add a stub to `lib.sh` for any new external command a target calls.

### Adding or changing a target
* Put it in `deploys/Makefile` (or in a subdirectory's Makefile **and** add the passthrough there; see above). Document it in [End-User Deployment](#end-user-deployment) as a `rellm deploy` command, with any new variable in [Environment Variables](#environment-variables). Then run `make -C deploys test` ([Tests](#tests)): it fails if a subdirectory target has no passthrough, a cluster-wide target is missing from `NAMESPACE_FREE_TARGETS`, or a documented command doesn't exist -- and add tests for anything with logic of its own.
* Validate arguments before touching the cluster, and anything destructive or that takes a site down should require explicit confirmation (`CONFIRM=<namespace>`, or `--yes` for scripts) after printing what it's about to do.
* Rolling out `deploys/k8s/` manifest changes is manual, per namespace (see [Rolling out manifest changes](#rolling-out-manifest-changes)); CI only bumps image tags.

### Credentials rule
This is a standing rule for contributors: a manifest or script must never contain an inline password, and a new consumer of a credential reads it from the relevant Secret via `secretKeyRef`. (See [Credentials](#credentials) for how every credential is generated.)

### Deploy scripts
Everything routine is a `make` target; the shell scripts under `deploys/` are for the things a Makefile recipe is too awkward for. They're organized by how often you'll run them:

* **`deploys/`** -- tasks that may recur, or that other things call:
  * `transition_jonline_namespace_to_central_storage.sh` (`make transition_backend_to_central_data`): moves a namespace onto [central storage](./central_storage/README.md), with downtime, verifying the copy and leaving the old storage untouched.
  * `.github/workflows/scripts/set_backend_images.sh`: what CI runs to deploy -- bumps the image tags of a namespace's `rellm`/`rellm-jobs`/`rellm-preview-generator` Deployments (`kubectl set image`) and nothing else.
  * `copy_server_configuration.sh` (`make copy_server_configuration`): copies one `server_configurations` column between two namespaces' databases (per-namespace or central). Convenience wrappers: `make copy_server_cluster_configuration` (`cluster_resources`, rewriting its `namespace_id` to the target) and `make copy_server_vapid_configuration` (`web_push_config`). All take `SOURCE=` and `TARGET=`.
  * `kubernetes_logs.sh` (`make view_server_logs`, `view_job_logs`, `view_preview_generator_logs`, `view_tmux_logs`): see [Viewing Logs](#viewing-logs).
  * `distributables.sh`: sourced by the Homebrew/Linux `rellm` launchers; not run directly. It also turns `rellm deploy`'s `-n`/`--namespace`, `--domain`, `--confirm`, `--tail` and `--lines` flags into `NAMESPACE=`, `DOMAIN=`, `CONFIRM=`, `LOG_TAIL=1` and `LOG_LINES=`.
* **`central_storage/provision_namespace.sh`** (`make create_backend_central_data`): creates a namespace's database/role, bucket/user and credentials Secret in central storage.
* **`central_storage/deprovision_namespace.sh`** (`make delete_backend_central_data`): the reverse -- permanently removes a namespace's central-storage data and credentials (smoke-test cleanup, retiring a site).
* **`data_migrations/`** -- one-time, per-namespace, manual data/credential migrations, kept as a record and for namespaces that haven't had them yet (`cutover_jonline_namespace.sh`, `rename_minio_pvc_to_object_storage.sh`, `adopt_legacy_data_credentials.sh`). Never run by CI or `make`.
* **`one_off_scripts/`** -- one-shot scripts that aren't data migrations (`rename_jonline_to_rellm.sh`), kept for reference.

Anything destructive or that takes a site down prints what it's about to do and asks you to confirm (or takes `--yes`). New scripts follow the same rules: validate every argument before touching the cluster, and never contain or print a hard-coded credential.
