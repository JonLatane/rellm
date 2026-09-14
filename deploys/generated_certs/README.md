# Generated Certs for Rellm
The easiest way to secure your Rellm distro is with Cert-Manager. There's also support for manually using your own certs, and using your own custom CA, though the latter is of course not useful for most use cases of Rellm 😁

## Use Cert-Manager (recommended)
Rellm's `make`-powered cert generation setup is built on Cert-Manager. You'll need to install it on your cluster via Helm to use them. Its existing tooling is designed to generate a wildcard cert setup (i.e., for `*.my.domain.tld`) for a domain managed by DigitalOcean Kubernetes Services (DOKS). 

(This setup should be easy to extend to Google/Amazon/MS Kubernetes offerings, as the only provider-specific constructs are `PersistentVolumeClaim`s and `LoadBalancer`s. It's also worth noting that the wildcard is important but not necessary, if you'd like to setup certs yourself. However, Rellm features may eventually demand multiple subdomains, at which point you need wildcards or per-subdomain certs for access to them.)

The following `make` commands should be run from inside this directory (`generated_certs`).

### Quick setup with Cert-Manager (DigitalOcean-specific for now)

These steps are all based off of using [the `Makefile` in this directory](https://github.com/JonLatane/rellm/blob/main/generated_certs/Makefile).
1. Point your DNS host (for instance, I use `jonline.io`), at the IP for your deployed `rellm` LoadBalancer instance. For the default Quick Start deploy, get it with: `kubectl describe service rellm -n rellm | grep 'LoadBalancer Ingress'`.
    * You need to be using DigitalOcean DNS for your domain and DigitalOcean Kubernetes Service (DOKS) to host.
2. Generate an API token with read+write access from [this DigitalOcean console page](https://cloud.digitalocean.com/account/api/tokens).
    * This, along with your email and the domain name, are all you need to get Cert-Manager up and running.
3. `make deploy_certmanager` to deploy CertManager to your cluster. (You can also follow [the official Cert-Manager docs](https://cert-manager.io/docs/installation/), but the Makefile just does what they say!)
4. `make deploy_certmanager_credential` and answer the prompts for your Kubernetes provider, domain, admin email, and API token (the token isn't echoed back and won't end up in your shell history since it's entered interactively, not passed as an argument).
    * To deploy the credential to a different namespace, run `NAMESPACE=my-k8s-namespace make deploy_certmanager_credential`.
    * Eventually quick setup will work with other providers, but for now `digitalocean` is the only valid value (just press enter to accept the default).

To validate that setup worked, simply run `kubectl get certificates`, which should yield something like:

```
NAME                       READY   SECRET                  AGE
rellm-letsencrypt-cert   True    rellm-generated-tls   30m
```

Want to contribute to quick setup for other cloud providers? It should only take a few terminal commands. Simply duplicate [the digitalocean commands in the certs Makefile](https://github.com/JonLatane/rellm/blob/0626a204483a473dd30906815613dad3c3a6b224/generated_certs/Makefile#L32-L45) and [the issuer+certificate YAML template used for DigitalOcean](https://github.com/JonLatane/rellm/blob/main/generated_certs/k8s/cert-manager.digitalocean.template.yaml), update them to work with how your provider does the Certbot DNS01 challenge, and it should all work quickly!

### Manual/Advanced setup with Cert-Manager
1. Point your DNS host (for instance, I use `be.jonline.io`), at the IP for your deployed `rellm` LoadBalancer instance. For the default Quick Start deploy, get it with: `kubectl describe service rellm -n rellm | grep 'LoadBalancer Ingress'`.
2. [Install Cert-Manager](https://cert-manager.io/docs/installation/).
    * Currently their page says: `kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml`.
3. Securely store your DNS provider's credentials.
    1. ***Disable history in your shell***.
        * For ZSH or Bash, simply `unset HISTFILE`.
    2. Generate and store your Cert-Manager-supported DNS provider's credentials.
        * DigitalOcean:
            * [Get an access token here](https://cloud.digitalocean.com/account/api/tokens).
            * Base64-encode it with `echo -n '<your DigitalOcean API token>' | base64`
            * Save it to K8s with `kubectl create secret generic digitalocean-dns --from-literal=access-token=<your Base64-encoded token> -n rellm`. (If you deployed to a namespace other than `rellm`, change it here.)
        * Other DNS providers: TBD. Search the web for "`<your provider> cert-manager dns01 wildcard`" for a start! The idea is to get your Cert-Manager/DNS provider to issue a cert for `yourdomain.com` and save it to the TLS secret `rellm-generated-tls` in the `rellm` namespace.
            * Contribute please 🙏🏻 Make a PR with your instructions here, a `backend/k8s/cert-manager.<your-provider>.template.yaml`, and new corresponding `make` targets for the next step!
4. Generate your Cert-Manager authority and certificate from the template included here, and apply them to your cluster.
    * DigitalOcean: `make deploy_certmanager_credential_digitalocean_prepare deploy_certmanager_credential_digitalocean_apply` and answer the domain/email prompts. (If you deployed to a namespace other than `rellm`, prefix your command with `NAMESPACE=my_namespace`.)
5. Wait for your cert secret to be generated by Cert-Manager. In the default setup, it will appear in `get secret rellm-generated-tls -n rellm` once it's generated.
    * If something goes wrong, `kubectl describe certificate rellm-letsencrypt-cert -n rellm` to see details on what's going on with certificate generation.
6. `make restart_backend` to use the Cert-Manager certificates.
7. You can validate your install with `make deploy_test_be`, similar to with an unsecured deployment. But now you must specify the domain. (By default, it targets your deployed external IP, and your domain cert isn't valid against an IP address.) So, simply do `TEST_GRPC_TARGET=example.domain:27707 make deploy_test_be`.

## Use certs from another CA
Perhaps you have a `server.pem` and `server.key` from your own CA. Make sure to specify the domain name you want the certs for (it can be a wildcard).

1. Ensure this directory has a `server.key` and your updated `server.pem` from your CA.
2. From the root of the repo, `make certs_server_store_in_k8s restart_backend` to use your certs.
    * You can `make certs_delete_from_k8s restart_backend` to switch back to non-TLS mode.

## Use your own custom CA
You probably don't want to do this. It's a *very* specific use case. The only time you'd want to use a custom CA is to deploy a custom version of the Flutter app that contains a community-specific encryption key. 

That said, to deploy with your own custom CA (i.e. generate your own `ca.key` and overwrite the existing `ca.pem` with your own here):

1. Update `server.csr.conf` and `server.extfile.conf` to point to your domain. (If you ask me for a cert, I do this temporarily.)
2. From the root of the repo, `make certs_generate`.
    * This generates `ca.key`, `ca.pem`, `server.key`, and `server.pem`.
    * You can `make certs_ca_generate` or `make certs_server_generate` to generate either set of public/private keys independently. (If you ask me for a cert, I do the latter and send you the `server.key` and `server.pem`.)
3. Finally, `make certs_store_in_k8s` to store them, and `make restart_backend` to restart your instance.
    * You can `make certs_ca_store_in_k8s` or `make certs_server_store_in_k8s` similarly.
4. You will need to provide both your `ca.pem` to end users if they use the official Rellm app. Alternatively, you could ship your own Rellm app with your own `ca.pem`.