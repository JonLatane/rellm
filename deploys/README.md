# Rellm Deploys

- [Rellm Deploys](#rellm-deploys)
  - [Basic Deployment](#basic-deployment)
    - [Deploying to namespaces other than `rellm`](#deploying-to-namespaces-other-than-rellm)
    - [Credentials](#credentials)
  - [Validating your deployment](#validating-your-deployment)
    - [Kubernetes service statuses](#kubernetes-service-statuses)
      - [External IP Management](#external-ip-management)
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
  - [Deploy scripts](#deploy-scripts)

Rather than requiring Helm, Ansible, Terraform, or other orchestration layers, Rellm deployment takes a more primitive route. Rellm deployment is built so you can simply maintain one cloned Rellm repo per cluster whose deployments you want to manage. Within your cluster's repo, you'll simply use `make` to deploy:

* Clone this repo.
* `cd deploys && NAMESPACE=rellm make create_backend_data create_internal_backend([^_]) to create backing Postgres and object storage/S3 instances and your BE instance. (You actually don't have to `cd deploys` because the main `Makefile` has some passthroughs!)
    * `NAMESPACE` is required (no default) - this deploys Postgres, object storage and Rellm to whichever namespace you name, e.g. `NAMESPACE=mynamespace make create_backend_data create_internal_backend([^_]).
    * For "production-ready" performance you can (and should) skip the `create_backend_data` part and instead configure external, managed Postgres and/or object storage/S3 servers.

See [the Cert-Manager integration README](./generated_certs/README.md) for more info on generating certs. At a high level, for a K8s deploy, `generated_certs/Makefile` will simply generate Cert-Manager K8s YAML to `deploys/generated_certs/k8s/cert-manager.\[digitalocean\].\[my-domain.com\].generated.yaml`. Applying that YAML (also doable through the `Makefile`) sets up K8s/Cert-Manager to auto-generate the certs for your Rellm instance in its namespace where it will look for them.

As a user or a contributor, it's helpful to understand that Rellm deployment is built upon:

* `make` and the `Makefile` targets in this `deploys/` directory and its subdirectories, which use/require:
  * `sed`
  * `jq`
  * `kubectl`
  * `openssl` (generating credentials)
  * `mc`, the MinIO Client (`brew install minio/stable/mc`) -- only for [central storage](./central_storage/README.md) provisioning/transitions
* `Dockerfile`s in `deploys/docker`
  * As a user, these are really just for reference, as you'll likely be deploying pre-built images from [jonlatane/rellm](https://hub.docker.com/r/jonlatane/rellm).
* Kubernetes `.yml` files in `deploys/k8s` and `deploys/generated_certs/k8s` (for using Rellm's Cert-Manager integration)
  * `.template.yml` files are used to generate `.yml` files for managing your own deployment.
* 

Virtually all deployment-related targets will involve `make` calling `kubectl` with either predefinied `.yml`, or after modifying `.template.yml` files.

## Basic Deployment
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

To begin setup, first clone this repo:

```bash
git clone https://github.com/JonLatane/rellm.git
cd rellm
```

Next, from the repo root, to create Postgres, object storage and two load-balanced Rellm servers in the namespace `rellm` (plus a few recurring jobs), run:

```bash
# THIS STEP WILL COST MONEY WITH MOST KUBERNETES PROVIDERS. ($12/mo. at DigitalOcean)
# The create_external_backend Make target, specifically, will create the Joline service as a K8s LoadBalancer.
# Of course, it costs nothing to use Minikube.
# To deploy for use with a different ingress (say, a shared nginx, or Rellm's pending internal LB), use create_internal_backend or deploy_be_internal_insecure_create to deploy it as a K8s ClusterIP instead.
# NAMESPACE is required (no default) - pick whichever namespace you want this deployed to.
NAMESPACE=rellm make create_backend_data create_external_backend
```

That's it! You've created object storage and Postgres servers (with randomly generated credentials -- see [Credentials](#credentials)) along with a Rellm instance that *doesn't have TLS yet*, so ***passwords and auth tokens will be sent in plain text*** (You should secure it immediately if you care about any data/people, but feel free to play around with it until you do! Simply `NAMESPACE=rellm make delete_backend_data create_backend_data restart_backend` to reset your server's data.) Because Rellm is a very tiny Rust service, it will all be up within seconds. Your Kubenetes provider will probably take some time to assign you an IP, though.

### Deploying to namespaces other than `rellm`
`NAMESPACE` is required (no default) for every `deploys/Makefile` target, so you always pick the namespace explicitly: `NAMESPACE=my_namespace make create_backend_data create_external_backend` to deploy to `my_namespace`. This should work for any of the `make deploy_*` targets in Rellm.

### Credentials
**No credential is ever checked into this repo, hand-typed, or reused between deployments -- every one is generated, randomly, by a Make target or script here.** (This is a standing rule for contributors, too: a manifest or script must never contain an inline password, and a new consumer of a credential reads it from the relevant Secret via `secretKeyRef`.)

* **Per-namespace deploys** (`create_backend_data`, and the `create_*_backend` targets, which run it first): `create_backend_data_credentials` generates a random Postgres password and object storage credentials into a `rellm-data-credentials` Secret in the namespace. The Postgres/object storage manifests and the server manifests all read it via `secretKeyRef`; the dump/restore targets (`dump_backend_postgres`, ...) read the password from the same Secret (or take `PG_PASSWORD=...`). It **never regenerates an existing Secret**: Postgres and the object storage server only read their credentials when initializing an empty volume, so a "new" value would silently stop matching the real one.
* **[Central storage](./central_storage/README.md)**: the shared instances' own admin credentials are random Secrets in `rellm-storage`, and every namespace on them gets its own Postgres role and object storage user -- named after the namespace, random passwords, each restricted to only that namespace's database/bucket -- in a `rellm-central-data` Secret.
* **Getting them back out:** `make get_all_storage_credentials` prints every one of those Secrets, decoded, across all namespaces (no `NAMESPACE` needed). Run it and put the output in a password manager -- these Secrets are the only copy. In particular, deleting a namespace (`kubectl delete namespace`) deletes its Secret while the data volumes survive (`reclaimPolicy: Retain`), and without the saved password you can't get back into that Postgres data.
* **Namespaces deployed before this existed** have their credentials inline in the running Deployments/StatefulSets. Run `deploys/data_migrations/adopt_legacy_data_credentials.sh <namespace>` once per namespace *before its next manifest rollout* (`make update_*`; see [Rolling out manifest changes](#rolling-out-manifest-changes)) -- it creates the Secret from the namespace's live values (verifying they all agree; nothing is restarted or changed) so the new manifests keep working against the same data. CI's image-only deploys don't need it. Those inline values were the old checked-in defaults, so treat them as compromised: the real fix is moving the namespace to central storage ([`transition_jonline_namespace_to_central_storage.sh`](./central_storage/README.md#transitioning-an-existing-namespace)), which issues fresh random credentials.
* **Rotating** a credential means changing it in the running server *and* the Secret (Postgres: `ALTER ROLE ... PASSWORD`; object storage: the server's root credentials env / `mc admin user`), then restarting the consumers. There's no target for it yet -- and never delete a `rellm-*credentials` Secret while its data volume lives on.

## Validating your deployment
### Kubernetes service statuses
To see *everything* you just deployed (object storage, postgres, Rellm server and background cron jobs), run `NAMESPACE=rellm make get_backend_all`. It should look something like this (with fewer jobs after a fresh install, probably):

```bash
$ NAMESPACE=rellm make get_backend_all
kubectl get all -n rellm
NAME                                                  READY   STATUS        RESTARTS   AGE
pod/delete-expired-tokens-27742795--1-nlkh6           0/1     Completed     0          11m
pod/delete-expired-tokens-27742800--1-tpplp           0/1     Completed     0          6m49s
pod/delete-expired-tokens-27742805--1-dgrsb           0/1     Completed     0          109s
pod/generate-preview-images-27721161--1-2hqgq         0/1     Error         0          15d
pod/generate-preview-images-27721161--1-6fwvq         0/1     Error         0          15d
pod/generate-preview-images-27721161--1-kxtvt         0/1     Error         0          15d
pod/generate-preview-images-27721161--1-mpnbv         0/1     Error         0          15d
pod/generate-preview-images-27721161--1-sg7rz         0/1     Error         0          15d
pod/generate-preview-images-27721161--1-t24th         0/1     Error         0          15d
pod/generate-preview-images-27742804--1-q8vdn         0/1     Completed     0          2m49s
pod/generate-preview-images-27742805--1-tbbvm         0/1     Completed     0          109s
pod/generate-preview-images-27742806--1-qrrnx         0/1     Completed     0          49s
pod/rellm-7f69759bd7-x64nd                          1/1     Running       0          30s
pod/rellm-7f69759bd7-x6scq                          1/1     Running       0          36s
pod/rellm-c4b798878-l6xhk                           1/1     Terminating   0          53m
pod/rellm-c4b798878-tg5qf                           1/1     Terminating   0          53m
pod/rellm-expired-token-cleanup-27742795--1-l8fzs   0/1     Completed     0          11m
pod/rellm-expired-token-cleanup-27742800--1-x6gch   0/1     Completed     0          6m49s
pod/rellm-expired-token-cleanup-27742805--1-hd2wj   0/1     Completed     0          109s
pod/rellm-object-storage-84685f9bd4-8knxq           1/1     Running       0          4d22h
pod/rellm-postgres-bf6cb7679-l6mcb                  1/1     Running       0          53m

NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP       PORT(S)                                                     AGE
service/rellm            LoadBalancer   10.245.199.164   178.128.137.194   27707:30679/TCP,443:32401/TCP,80:30932/TCP,8000:30414/TCP   20d
service/rellm-object-storage  LoadBalancer   10.245.220.21    174.138.106.145   9000:32603/TCP                                              2d
service/rellm-postgres   ClusterIP      10.245.198.74    <none>            5432/TCP                                                    53m

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/rellm            2/2     2            2           20d
deployment.apps/rellm-object-storage  1/1     1            1           4d22h
deployment.apps/rellm-postgres   1/1     1            1           53m

NAME                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/rellm-54d8b475bb           0         0         0       4d6h
replicaset.apps/rellm-6b6655cd79           0         0         0       2d23h
replicaset.apps/rellm-6bb49b7c9c           0         0         0       24h
replicaset.apps/rellm-6c8899f68c           0         0         0       4d2h
replicaset.apps/rellm-6f5c8955f7           0         0         0       3d22h
replicaset.apps/rellm-74557695b            0         0         0       2d23h
replicaset.apps/rellm-77585dcf8            0         0         0       3d20h
replicaset.apps/rellm-7bff45979c           0         0         0       4d6h
replicaset.apps/rellm-7f69759bd7           2         2         2       38s
replicaset.apps/rellm-7f6d9d4cbd           0         0         0       3d23h
replicaset.apps/rellm-c4b798878            0         0         0       53m
replicaset.apps/rellm-object-storage-84685f9bd4     1         1         1       4d22h
replicaset.apps/rellm-postgres-bf6cb7679   1         1         1       53m

NAME                                          SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/delete-expired-tokens           */5 * * * *   False     0        113s            15d
cronjob.batch/generate-preview-images         * * * * *     False     0        53s             15d
cronjob.batch/rellm-expired-token-cleanup   0/5 * * * *   False     0        113s            20d

NAME                                               COMPLETIONS   DURATION   AGE
job.batch/delete-expired-tokens-27742795           1/1           4s         11m
job.batch/delete-expired-tokens-27742800           1/1           4s         6m53s
job.batch/delete-expired-tokens-27742805           1/1           4s         113s
job.batch/generate-preview-images-27721161         0/1           15d        15d
job.batch/generate-preview-images-27742804         1/1           1s         2m53s
job.batch/generate-preview-images-27742805         1/1           4s         113s
job.batch/generate-preview-images-27742806         1/1           1s         53s
job.batch/rellm-expired-token-cleanup-27721007   0/1           15d        15d
job.batch/rellm-expired-token-cleanup-27742795   1/1           4s         11m
job.batch/rellm-expired-token-cleanup-27742800   1/1           5s         6m53s
job.batch/rellm-expired-token-cleanup-27742805   1/1           4s         113s
```

#### External IP Management
Use `NAMESPACE=rellm make get_backend_external_ip` to see what your service's external IP is (until set, it will return `<pending>`).

```bash
$ NAMESPACE=rellm make get_backend_external_ip
188.166.203.133
```

Finally, once the IP is set, to test the service from your own computer, use `make deploy_test_be_unsecured` to run tests against that external IP (you need `grpcurl` for this; `brew install grpcurl` works for macOS):

```bash
$ NAMESPACE=rellm make deploy_test_be
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

## Pointing a domain at your deployment
Before you can secure with LetsEncrypt, you need to point a domain at your Rellm instance's IP. Again, you can get the IP with `NAMESPACE=rellm make get_backend_external_ip`, and create your DNS records with your DNS provider. If you're choosing a DNS provider, it's worth noting that [I recommend DigitalOcean DNS (sponsored link)](https://m.do.co/c/1eaa3f9e536c) and Rellm has scripts for it. However, any [Cert-Manager](http://cert-manager.io) supported DNS provider (for the LetsEncrypt dns01 challenge) should be pretty easy to set up.

Continue to the next section for more info about setting up encryption and its relation to your DNS provider.

## Securing your deployment
Rellm uses 🐕💩EZ, boring normal TLS certificate management to negotiate trust around its decentralized social network. If you're using DigitalOcean DNS you can be setup in a few minutes.

See [`deploys/generated_certs/README.md`](https://github.com/JonLatane/rellm/tree/main/deploys/generated_certs) for quick TLS setup instructions, either [using Cert-Manager (recommended)](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/README.md#use-cert-manager-recommended), [some other CA](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/README.md#use-certs-from-another-ca) or [your own custom CA](https://github.com/JonLatane/rellm/blob/main/generated_certs/README.md#use-your-own-custom-ca) (i.e. to distribute a secure, network-specific Flutter app and only let users in through that - custom CAs would break/disable the web app entirely).

See [`backend/README.md`](https://github.com/JonLatane/rellm/blob/main/backend/README.md) for more detailed descriptions of how the deployment and TLS system works.

## Deleting your deployment
You can delete your Rellm deployment piece by piece with `NAMESPACE=my_namespace make delete_backend delete_backend_postgres` or simply `kubectl delete namespace my_namespace`. Before deleting a namespace's storage, save its credentials (`make get_all_storage_credentials` -- see [Credentials](#credentials)).

Once a namespace has been moved to central storage and you've verified it, `NAMESPACE=my_namespace CONFIRM=my_namespace make delete_backend_data_pvcs` removes its old per-namespace Postgres/object storage and their PVCs (it refuses unless the namespace really is on central storage, and keeps the underlying volumes as `Released` PVs until you delete them yourself).


## Multiple Deployments
As mentioned in [Deploying to namespaces other than `rellm`](#deploying-to-namespaces-other-than-rellm): to deploy anything to a namespace other than `rellm`, simply add the environment variable `NAMESPACE=my_namespace`. So, for the initial deploy, `NAMESPACE=my_namespace make create_backend_data create_external_backend` to deploy to `my_namespace`. This should work for any of the `make deploy_*` targets in Rellm.

Note that multiple *external* deployments will each have a Kubernetes LoadBalancer. On many providers, this is relatively expensive (an external IP, $12/mo on DigitalOcean). Other Makefile targets include `create_internal_backend` and `deploy_be_internal_insecure_create` (the latter of which will specifically ignore K8s-stored TLS certificates, to save CPU time by not encrypting interal services).

### Rellm Ingress: sharing one LoadBalancer across many domains (recommended)
[`deploys/ingress/`](./ingress/README.md) sets up a single, shared [Traefik](https://traefik.io) ingress that lets any number of Rellm instances - each still in its own namespace, each with its own domain, Postgres, object storage and Cert-Manager certs - share **one** external IP/LoadBalancer instead of one each. Each backend keeps terminating its own TLS exactly as it does today (`create_internal_backend`/`update_internal_backend`); the ingress only reads the plaintext SNI hostname from the TLS handshake to route the still-encrypted bytes to the right namespace, so no certs need to move, be duplicated, or change hands.

```bash
# Once per cluster:
cd deploys/ingress && make create_ingress
# Once per domain, after that domain's own basic deployment already exists:
NAMESPACE=my_namespace DOMAIN=my.domain.example.com make add_ingress_domain
```

See [`deploys/ingress/README.md`](./ingress/README.md) for the full walkthrough, including how to cut a domain over from its own LoadBalancer without downtime.

### Central Storage: sharing Postgres/object storage across many namespaces
Each namespace's Postgres and object storage above is its own StatefulSet - 2 PVCs per namespace. Most managed Kubernetes offerings cap how many PVCs a cluster can attach at all (DigitalOcean's DOKS: 15), so that runs out fast once you're hosting more than a handful of domains, regardless of how cheap or expensive each individual domain's traffic is. [`deploys/central_storage/`](./central_storage/README.md) sets up one shared Postgres + object storage instance (2 PVCs, full stop) that any number of *new* namespaces can point at instead, each with its own database and bucket (named after the namespace) inside the shared instance rather than an instance of its own.

```bash
# Once per cluster:
cd deploys/central_storage && make create_central_storage
# Once per new namespace, instead of create_backend_data create_internal_backend:
NAMESPACE=my_namespace make create_backend_central_data create_internal_central_data_backend
```

This creates no shared credentials anyone has to know: the shared instances' admin credentials are random Secrets, and each namespace gets its own restricted Postgres role/object storage user (see [Credentials](#credentials)). Existing per-namespace deployments are untouched until you move them with `NAMESPACE=my_namespace make transition_backend_to_central_data` (site is down for the duration; the old storage is left running for you to verify and later remove with `delete_backend_data_pvcs`). Known gap: `dump_backend_postgres`/`restore_backend_postgres`/`upgrade_backend_postgres` only work on a namespace's own Postgres -- central storage has PVC size/resize targets (`get_central_*_pvc_size`, `resize_central_*_pvc`) but no backup or upgrade path yet. See [`deploys/central_storage/README.md`](./central_storage/README.md) for the full walkthrough.

### Example Kubernetes Cluster Setups
#### K8s cluster with multiple Kubernetes LoadBalancers (without a shared ingress)
This is how Rellm was originally deployed, and still is by default for a single domain.

![K8s cluster with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Kubernetes_Deployment.svg)

#### K8s cluster with multiple Rellm servers/deployments behind a single shared LoadBalancer
This is what [`deploys/ingress/`](./ingress/README.md) sets up.
![System with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg)

## Maximally-Efficient Configuration
This is how the Rellm author's own cluster runs, and the setup to use if you want to host *many* sites cheaply: **one** LoadBalancer, **one** mail server and **one** Postgres/object storage pair shared by every site, so each additional site costs little more than its own pods.

| Shared piece | Namespace | What it replaces (per site) | Docs |
|---|---|---|---|
| **Traefik** - one `LoadBalancer`/external IP routing every domain by SNI/`Host`, plus plain TCP `:25` for mail | `traefik-ingress` | a `LoadBalancer` per site (~$12/mo each) | [`ingress/`](./ingress/README.md) |
| **Stalwart** - one internet-facing SMTP server; hands each domain's mail to that site's `rellm` | `rellm-email` | a mail server per site | [`email/`](./email/README.md) |
| **Central storage** - one Postgres + one Silo (2 PVCs total); each site gets its own database/bucket and a role/user restricted to just that | `rellm-storage` | 2 PVCs per site (DOKS caps a cluster at 15) | [`central_storage/`](./central_storage/README.md) |

Each site is then just a namespace holding `rellm` (x2), `rellm-jobs`, `rellm-preview-generator`, its `rellm-tls` certificate Secret and its `rellm-central-data` credentials Secret. See the [diagram](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg). Sites deploy from CI by image tag only ([Rolling out manifest changes](#rolling-out-manifest-changes)).

Commands below assume `kubectl` points at the right cluster (`kubectl config current-context`). One-time setup runs from the **repo root** (the root `Makefile` has passthroughs and needs no `NAMESPACE`); per-site steps run from `deploys/` with `NAMESPACE` set.

### One-time cluster setup
Do these once per cluster, in this order.

1. **Central storage** (needs `openssl` locally; the commands in [Adding a site](#adding-a-site) also need `mc`, `brew install minio/stable/mc`). Generates random admin credentials into Secrets in `rellm-storage` and creates the shared Postgres and Silo:

   ```bash
   make create_central_storage
   make -C deploys/central_storage wait_central_postgres_ready wait_central_object_storage_ready
   ```

   Defaults are 10Gi (Postgres) / 20Gi (Silo); grow them later with `make -C deploys/central_storage resize_central_*_pvc SIZE=...` (grow-only).
2. **Traefik ingress** - the single shared LoadBalancer:

   ```bash
   make create_ingress
   make get_ingress_external_ip      # the one IP every domain's A record points at
   ```
3. **Cert-Manager** - issues each site's Let's Encrypt certificate (installed once; each site's DigitalOcean credential is created per site below):

   ```bash
   make -C deploys/generated_certs deploy_certmanager
   ```
4. **Stalwart** (shared mail server). It sits *behind* the Traefik you just installed (port 25 enters through Traefik's `smtp` entrypoint), so do this after step 2.
   1. Pre-set Stalwart's admin password. Choose your own - there is deliberately no default, and `add_email_domain` below authenticates with it:

      ```bash
      ADMIN_PASSWORD='<a long random password>' make create_email_admin_secret
      ```
      This must happen **before** `create_email`: Stalwart only reads it on a completely empty data volume.
   2. Install it:

      ```bash
      make create_email
      ```
   3. Open its admin UI / setup wizard (`ClusterIP`-only, never exposed publicly) and log in as `admin` with that password:

      ```bash
      make deploy_email_admin_port_forward     # then open http://localhost:8080
      ```
      On a fresh volume Stalwart boots into the wizard. Choose **RocksDB** for storage (its PVC holds only Stalwart's own config and queue - never user mailboxes) and send logging to the **console** so `kubectl logs -n rellm-email deployment/stalwart` shows something. Stop the port-forward when done.
   4. Confirm your provider lets inbound traffic reach port 25 (some block it by default and need a ticket), and that the Traefik LoadBalancer forwards TCP `:25`. `make deploy_email_get_ip` prints the IP your MX records resolve to - it's the same ingress IP.
   5. Smoke test, bypassing DNS: `openssl s_client -connect <ingress-ip>:25 -crlf` should show Stalwart's `220 ... ESMTP` banner. Full details and troubleshooting: [`email/README.md`](./email/README.md).

### Adding a site
Per site (shown for namespace `my-site` and domain `my-site.example.com`; the namespace name becomes its database, bucket and credentials' name, so use lowercase letters, digits and `-`, at least 3 characters). From `deploys/`:

```bash
cd deploys
export NAMESPACE=my-site
export DOMAIN=my-site.example.com
```

**DNS first.** Point an `A` record for `$DOMAIN` at the ingress IP (`make get_ingress_external_ip`). Certificates use DNS-01 through DigitalOcean (for the apex and `*.$DOMAIN`), so `$DOMAIN` must be a DigitalOcean DNS zone - delegate it with `NS` records from wherever the parent domain lives - and the API token you give Cert-Manager needs write access to it.

1. **Provision the site's slice of central storage** - database + role, bucket + user, and a `rellm-central-data` Secret with fresh random credentials, each restricted to only this site's data (also creates the namespace):

   ```bash
   make create_backend_central_data
   ```
2. **Deploy the backend** (reads that Secret):

   ```bash
   make create_internal_central_data_backend
   ```
3. **TLS.** Prompts for the provider (press Enter for `digitalocean`), your DigitalOcean API token (hidden), the domain and an admin email. The certificate can take a few minutes; the pods read it at startup, so restart them once it's `READY`:

   ```bash
   make deploy_certmanager_credential
   kubectl get certificate -n $NAMESPACE -w     # wait for READY=True
   make restart_backend
   ```
4. **Route the domain through Traefik:**

   ```bash
   make add_ingress_domain
   ```

   Verify with `curl -I https://$DOMAIN` and `grpcurl $DOMAIN:27707 list`. If the site 404s or hangs right after, bounce Traefik (`kubectl rollout restart deployment traefik -n traefik-ingress`) - it briefly interrupts every domain, so only if needed.
5. **Email (optional)** - Stalwart must already be set up (above) and step 2 deployed, since the mail hook calls this namespace's `rellm` on port 27705:

   ```bash
   make add_email_domain
   make list_email_domains          # confirm it's listed
   ```

   Then add these records in the DNS zone:

   | Type | Name | Value |
   |---|---|---|
   | `MX` | `@` | `my-site.example.com.` priority `10` (the `A` record sends it to Traefik; any name resolving to the ingress IP works) |
   | `TXT` | `@` | `v=spf1 mx ~all` |
   | `TXT` | `_dmarc` | `v=DMARC1; p=none; rua=mailto:you@example.com` |

   Mail is receive-only. Test before relying on DNS - create a real user on the site first (mail to an unknown username is accepted, then silently dropped), then:

   ```bash
   swaks --to <username>@$DOMAIN --server "$(make get_ingress_external_ip)" --header "Subject: Test" --body "Test message."
   kubectl logs -f deployment/stalwart -n rellm-email      # accepted, hook fired?
   kubectl logs -f deployment/rellm -n $NAMESPACE          # POST /email arrived?
   ```

   `550 5.1.2 Relay not allowed` with the domain listed means Stalwart cached an earlier "no such domain": `make deploy_email_restart`, then retry.
6. **Save the credentials** - these Secrets are the only copy: `make get_all_storage_credentials`.
7. **Keep it current in CI.** CI only bumps image tags on namespaces it knows about, so add a deploy job for the new namespace in `.github/workflows/server_ci_cd.yml` (copy an existing one, such as `deploy_rellm_org`). Until then the site runs the image from step 2 (the manifests' base version).

### Day-to-day
- **Deploys:** push to `main`; CI bumps each site's image tags. Manifest changes are rolled out deliberately - see [Rolling out manifest changes](#rolling-out-manifest-changes).
- **Capacity:** `make -C deploys/central_storage get_central_postgres_pvc_size get_central_object_storage_pvc_size`, and grow with the `resize_central_*_pvc` targets. The central Postgres and Silo are shared by every site and have no backup or upgrade path yet (see [Central Storage](#central-storage-sharing-postgresobject-storage-across-many-namespaces)).
- **Retiring a site:** delete its namespace, then `NAMESPACE=my-site CONFIRM=my-site make delete_backend_central_data` to permanently remove its database, bucket and credentials. `make remove_ingress_domain` and `make remove_email_domain` take it out of Traefik and Stalwart.

## Upgrading your deployed PostgreSQL
_(This section covers a namespace's own Postgres. [Central storage](./central_storage/README.md)'s shared Postgres has no dump/upgrade targets yet.)_

The Postgres image tag lives in `k8s/k8s-postgres-$(K8S_PROVIDER).yaml`. For a **minor** version bump (e.g. `17.5` → `17.6`), just edit the tag and run `NAMESPACE=rellm make update_backend_postgres`. For a **major** version bump (e.g. `14` → `17`), the on-disk data format changes, so don't just `update_backend_postgres` - use:

```bash
NAMESPACE=my_namespace make upgrade_backend_postgres
```

This handles the whole migration: it dumps your current database (via a temporary port-forward, no `kubectl exec` needed), stops the app and the old Postgres, brings up the new version (initdb'd fresh on a new PVC subPath, so the old data directory is never touched), restores the dump into it, then restarts the app. Your old version's data stays on disk as an instant rollback until you're confident in the new one, at which point `make delete_backend_postgres_old_data NAMESPACE=my_namespace` permanently deletes it.

## Rolling out manifest changes
CI deploys are **image-only**: `.github/workflows/server_ci_cd.yml` runs `kubectl set image` for each namespace's `rellm`, `rellm-jobs` and `rellm-preview-generator` Deployments and never applies a manifest. That makes a CI deploy independent of how a namespace is configured (central or own storage) and safe during a storage transition -- it can't change replicas, env, credentials or wiring, so a site you've scaled down for a cutover stays down. The cost: **changes under `deploys/k8s/` (a new env var, port, Service entry, replica count, a new Deployment...) are not rolled out by CI** -- the new image runs against the old manifests until you roll them out. The `manifest_change_notice` CI job warns on any push that touches those files. To roll out, per namespace:

```bash
NAMESPACE=my_namespace make update_internal_central_data_backend
```

This regenerates that namespace's manifests from the templates and applies them, **keeping whatever images the Deployments are running** (CI's `<version>-<sha>` tags) rather than resetting them to the manifests' base version (`REPO_IMAGES=1` to deploy the manifests' tags as written). Do it for every namespace, and do it *before* (or together with) deploying code that needs the new config. A brand-new namespace has no Deployments for CI to update: create it with `make create_backend_central_data create_internal_central_data_backend`, then CI keeps its image current.

## Deploy scripts
Everything routine is a `make` target; the shell scripts under `deploys/` are for the things a Makefile recipe is too awkward for. They're organized by how often you'll run them:

* **`deploys/`** -- tasks that may recur, or that other things call:
  * `transition_jonline_namespace_to_central_storage.sh` (`make transition_backend_to_central_data`): moves a namespace onto [central storage](./central_storage/README.md), with downtime, verifying the copy and leaving the old storage untouched.
  * `.github/workflows/scripts/set_backend_images.sh`: what CI runs to deploy -- bumps the image tags of a namespace's `rellm`/`rellm-jobs`/`rellm-preview-generator` Deployments (`kubectl set image`) and nothing else.
  * `copy_server_configuration.sh` (`make copy_server_configuration`): copies one `server_configurations` column between two namespaces' databases (per-namespace or central). Convenience wrappers: `make copy_server_cluster_configuration` (`cluster_resources`, rewriting its `namespace_id` to the target) and `make copy_server_vapid_configuration` (`web_push_config`). All take `SOURCE=` and `TARGET=`.
  * `distributables.sh`: sourced by the Homebrew/Linux `rellm` launchers; not run directly.
* **`central_storage/provision_namespace.sh`** (`make create_backend_central_data`): creates a namespace's database/role, bucket/user and credentials Secret in central storage.
* **`central_storage/deprovision_namespace.sh`** (`make delete_backend_central_data`): the reverse -- permanently removes a namespace's central-storage data and credentials (smoke-test cleanup, retiring a site).
* **`data_migrations/`** -- one-time, per-namespace, manual data/credential migrations, kept as a record and for namespaces that haven't had them yet (`cutover_jonline_namespace.sh`, `rename_minio_pvc_to_object_storage.sh`, `adopt_legacy_data_credentials.sh`). Never run by CI or `make`.
* **`one_off_scripts/`** -- one-shot scripts that aren't data migrations (`rename_jonline_to_rellm.sh`), kept for reference.

Anything destructive or that takes a site down prints what it's about to do and asks you to confirm (or takes `--yes`). New scripts follow the same rules: validate every argument before touching the cluster, and never contain or print a hard-coded credential.

