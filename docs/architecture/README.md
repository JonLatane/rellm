# Rellm Architecture
Rellm is generally setup to be deployed using Make atop `kubectl` and `jq` (and `graphviz`, if editing architecture diagrams in this directory).

## Application Architecture
This is how Rellm works on a client-server, in terms of interaction of the Browser/App, HTTP server, gRPC server, PostgreSQL DB, and object storage.

![Rellm Application Architecture](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Service_Architecture.svg)

## Deployment Management
[Deployment management logic lives in `deploys/`](https://github.com/JonLatane/rellm/tree/main/deploys). Essentially this is some readable `Makefile` stuff built atop `kubectl`.

### TLS Certificate Generation
[Generated certs live in `deploys/generated_certs`](https://github.com/JonLatane/rellm/tree/main/deploys/generated_certs). Generally, if  you want to deploy to your own Kubernetes cluster, and secure it with TLS, you should take a look at these docs. Cert-Manager for DigitalOcean with DigitalOcean DNS is done. It should be possible to do this for other hosts with Cert-Manager support.


## CI/CD (Continuous Integration and Delivery)
[CI/CD logic is defined in `.github/workflows/`](https://github.com/JonLatane/rellm/tree/main/.github/workflows). If you can set up a Kubernetes deployment with the instructions in [`deploys/`](https://github.com/JonLatane/rellm/tree/main/deploys), hooking into the Server

The main CI jobs behind Rellm are:

[![Server CI/CD Badge](https://github.com/jonlatane/rellm/actions/workflows/server_ci_cd.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/server_ci_cd.yml)
[![Proto Consistency Badge](https://github.com/jonlatane/rellm/actions/workflows/proto_consistency.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/proto_consistency.yml)

### CI For iOS, Android, macOS, Windows, and Linux
[![Flutter iOS Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_ios.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/flutter_ios.yml)
[![Flutter Android Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_android.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/flutter_android.yml)
[![Flutter macOS Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_macos.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/flutter_macos.yml)
[![Flutter Windows Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_windows.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/flutter_windows.yml)

## Example Kubernetes Cluster Setups
### K8s cluster with multiple Kubernetes LoadBalancers
This is how Rellm is currently deployed.

![K8s cluster with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Kubernetes_Deployment.svg)

### K8s cluster with multiple Rellm servers/deployments behind a single JBL LoadBalancer
Not yet implemented; an ongoing dev effort (that welcomes outside contributions)! See [the GitHub issue for more information](https://github.com/JonLatane/rellm/issues/15).
![System with multiple Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg)
