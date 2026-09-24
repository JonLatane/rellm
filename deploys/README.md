# Rellm Deploys

- [Rellm Deploys](#rellm-deploys)
  - [Basic Deployment](#basic-deployment)
    - [Deploying to namespaces other than `rellm`](#deploying-to-namespaces-other-than-rellm)
  - [Validating your deployment](#validating-your-deployment)
    - [Kubernetes service statuses](#kubernetes-service-statuses)
      - [External IP Management](#external-ip-management)
  - [Pointing a domain at your deployment](#pointing-a-domain-at-your-deployment)
  - [Securing your deployment](#securing-your-deployment)
  - [Deleting your deployment](#deleting-your-deployment)
  - [Multiple Deployments](#multiple-deployments)
    - [Rellm Ingress: sharing one LoadBalancer across many domains (recommended)](#rellm-ingress-sharing-one-loadbalancer-across-many-domains-recommended)
    - [Example Kubernetes Cluster Setups](#example-kubernetes-cluster-setups)
      - [K8s cluster with multiple Kubernetes LoadBalancers (without a shared ingress)](#k8s-cluster-with-multiple-kubernetes-loadbalancers-without-a-shared-ingress)
      - [K8s cluster with multiple Rellm servers/deployments behind a single shared LoadBalancer](#k8s-cluster-with-multiple-rellm-serversdeployments-behind-a-single-shared-loadbalancer)
  - [Upgrading your deployed PostgreSQL](#upgrading-your-deployed-postgresql)

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

That's it! You've created object storage and Postgres servers along with an *unsecured Rellm instance* where ***passwords and auth tokens will be sent in plain text*** (You should secure it immediately if you care about any data/people, but feel free to play around with it until you do! Simply `NAMESPACE=rellm make delete_backend_data create_backend_data restart_backend` to reset your server's data.) Because Rellm is a very tiny Rust service, it will all be up within seconds. Your Kubenetes provider will probably take some time to assign you an IP, though.

### Deploying to namespaces other than `rellm`
`NAMESPACE` is required (no default) for every `deploys/Makefile` target, so you always pick the namespace explicitly: `NAMESPACE=my_namespace make create_backend_data create_external_backend` to deploy to `my_namespace`. This should work for any of the `make deploy_*` targets in Rellm.

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
You can delete your Rellm deployment piece by piece with `NAMESPACE=my_namespace make delete_backend delete_backend_postgres` or simply `kubectl delete namespace my_namespace`.


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

### Example Kubernetes Cluster Setups
#### K8s cluster with multiple Kubernetes LoadBalancers (without a shared ingress)
This is how Rellm was originally deployed, and still is by default for a single domain.

![K8s cluster with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Kubernetes_Deployment.svg)

#### K8s cluster with multiple Rellm servers/deployments behind a single shared LoadBalancer
This is what [`deploys/ingress/`](./ingress/README.md) sets up.
![System with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg)

## Upgrading your deployed PostgreSQL
The Postgres image tag lives in `k8s/k8s-postgres-$(K8S_PROVIDER).yaml`. For a **minor** version bump (e.g. `17.5` → `17.6`), just edit the tag and run `NAMESPACE=rellm make update_backend_postgres`. For a **major** version bump (e.g. `14` → `17`), the on-disk data format changes, so don't just `update_backend_postgres` - use:

```bash
NAMESPACE=my_namespace make upgrade_backend_postgres
```

This handles the whole migration: it dumps your current database (via a temporary port-forward, no `kubectl exec` needed), stops the app and the old Postgres, brings up the new version (initdb'd fresh on a new PVC subPath, so the old data directory is never touched), restores the dump into it, then restarts the app. Your old version's data stays on disk as an instant rollback until you're confident in the new one, at which point `make delete_backend_postgres_old_data NAMESPACE=my_namespace` permanently deletes it.
