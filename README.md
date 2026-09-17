# <img src="https://rellm.org/favicon.png" alt="Rellm logo" height="32" align="top"/> Rellm [![Server CI/CD Badge](https://github.com/jonlatane/rellm/actions/workflows/server_ci_cd.yml/badge.svg)](https://github.com/jonlatane/rellm/actions/workflows/server_ci_cd.yml) [![gRPC Docs!](https://img.shields.io/badge/gRPC-protocol%20docs-information?labelColor={}&color=blue)](https://rellm.org/docs)

[![Rellm.org](https://rellm.org/info_shield?b6713cbc8)](https://rellm.org)
[![OakCity.social](https://oakcity.social/info_shield?b6713cbc8)](https://oakcity.social)
[![BullCity.social](https://bullcity.social/info_shield?b6713cbc8)](https://bullcity.social)
[![ATO.band](https://ato.band/info_shield?b6713cbc8)](https://ato.band)
[![Jonline.io](https://jonline.io/info_shield?b6713cbc8)](https://jonline.io)

[![Homebrew](https://img.shields.io/badge/macOS-Homebrew-purple?logo=homebrew&logoColor=white)](#macos-install-and-run-via-homebrew) [![Linux](https://img.shields.io/badge/Linux-Self%20Updating%20.tar.bz2-green?logo=linux&logoColor=white)](#linux-self-updateable-tarbz2-with-arm64-and-amd64-binaries-and-launcher)


[![DockerHub Server Images](https://img.shields.io/docker/v/jonlatane/rellm?label=dockerhub:rellm)](https://hub.docker.com/r/jonlatane/rellm/tags) [![DockerHub Preview Generator Images](https://img.shields.io/docker/v/jonlatane/rellm_preview_generator?label=dockerhub:rellm_preview_generator)](https://hub.docker.com/r/jonlatane/rellm_preview_generator/tags)


Rellm is an open-source, community-scale social network designed to be capable of "[delightfully federating](#delightful-federation)" with other Rellm instances/communities, Mastodon/ActivityPub servers, iCal calendars, RSS feeds, and more, making sharing between local-size instances easy. All web-facing features in Rellm - the Elm app, Tamagui/React app, the Flutter app, and Media endpoints - are written with easy-to-read AGPL code, `localStorage` (or system storage, for native Flutter apps), and neither set nor read cookies at all, ever. Thus, an unmodified Rellm server shouldn't need a cookie notice under the GDPR or CCPA. Moreover, any modified version of Rellm that *does* use cookies would violate the AGPL if the source weren't provided to users.

Meanwhile, in support of media creators/providers who might want to self-host Rellm for themselves or in a consortium (whether in lieu of or in addition to monolithic social media presence like YouTube or Twitch), Rellm's CORS support does still afford private media holders a basic way to control who can see their content. If I want to require you be on `ato.band` to listen to my band's music instead of letting you listen from `bullcity.social`, that's already a Web thing, and Rellm can give you a switch for it. Further, better Media permission/visibility controls could definitely be added, should, say, video creators or streamers want to migrate to self-hosting using a Rellm instance as their decentralized video platform to charge for premium content.

The "dev" instance is up at [Jonline.io](https://jonline.io). Three "production" instances are also at [BullCity.Social](https://bullcity.social), [OakCity.Social](https://oakcity.social), and [ATO.Band](https://ato.band). Unless I'm doing some testing with Jonline.io, all three should be configured to be able to federate with one another (or, for clients to federate between them). For anyone curious, all four (along with their corresponding Postgres and MinIO) live on a single-box DigitalOcean K8s instance. Between a single DigitalOcean "Droplet" for compute/memory, a Traefik LB, and 60¢ per server of storage (1GB Postgres + 5GB MinIO), it costs about $45/mo to run the 4 domains. Other than the cost to buy the new domain, any other new domains should just cost 60¢ more per month. (All also keep their media and HTML/CSS/JS behind Cloudflare's free CDN.)

[![Buy me a coffee!](https://img.shields.io/badge/🙏%20Buy%20me%20a%20coffee%20☕️-venmo-information?labelColor={}&color={})](https://account.venmo.com/u/Jon-Latane)
[![Buy me a beer!](https://img.shields.io/badge/🙏%20Buy%20me%20a%20beer%20🍺-paypal-information?labelColor={}&color={})](https://paypal.me/JLatane)

## Packages, Images & Deployments

Rellm can be run from source, via Homebrew, with a Linux binary package, or with Docker images.

At a high level, Rellm's CI/CD ([example run](https://github.com/JonLatane/rellm/actions/runs/29740971903)) is setup to do the following, stopping if there are issues:

1. Build and test the Rust BE, Elm FE and Tamagui/React FE.
2. Build a server Docker image and deploy it to [jonline.io](https://jonline.io).
    * The Docker images are minimal Debian images with a `rellm` server binary, as well as binaries for various jobs, used for the live deployments currently at [jonline.io](https://jonline.io), [bullcity.social](https://bullcity.social), and [oakcity.social](https://oakcity.social). Environment variables allow fairly straightforward configuration with Kubernetes.
3. Create a GitHub Release.
4. Create Homebrew & Linux packages, and deploy to [bullcity.social](https://bullcity.social) and [oakcity.social](https://oakcity.social).
    * The Homebrew/Linux `rellm` is actually a platform-specific, `bash`-based "thin launcher.
      * The `bash`-based `rellm` launcher provides tools for running the server, jobs, and admin tasks.
      * Homebrew/Linux rename the Rust `rellm` server binary to `rellm-server` (macOS) and `rellm-server-[arm64|amd64]` (Linux).
      * The launcher runs everything from an "install directory" which also contains the frontends (`/#{etc}/rellm/` for Homebrew, your extracted test directory or `~/.rellm-linux/` for the Linux package).
      * The Linux/macOS launchers store environment variables in `~/.rellm` and load them before starting the server or other services.
      * The install directory also bundles a full copy of [`deploys/`](https://github.com/JonLatane/rellm/tree/main/deploys), so `rellm deploy <targets...>` (requires `make`) can drive your own Kubernetes cluster without cloning the repo - see [Quick deploy to your own cluster](#quick-deploy-to-your-own-cluster).

### macOS: Install and Run via Homebrew

The Homebrew distro puts the Rellm server contents in `/#{etc}/rellm`, with a `bash`-based thin launcher for it at `#{bin}/rellm`. The launcher can set up your local Postgres DB with `createdb` and `dropdb` for you, and start a MinIO instance with `docker`. You will need to provide these yourself, but that's it.

Additional docs for the Rellm thin launcher can be found in [`docs/rellm_homebrew.sh`](https://github.com/JonLatane/rellm/blob/main/docs/rellm_homebrew.sh`) (which *is literally the launcher script that will become your `#{bin}/rellm`*, if you wanna PR any changes).

#### 2 minute startup with Homebrew

**Prerequisites for your `$PATH`:**

* Installation: `brew`
* Postgres autoconfiguration: `createdb`, `dropdb`
* Docker/MinIO autoconfiguration: `docker`
* `convert_media_sizes` background job (images): ImageMagick (`brew install imagemagick`), providing either `magick` or the legacy `convert`+`identify` pair. Optional - the job just skips images (logging an error) if it's missing.
* `convert_media_sizes` background job (video): `ffmpeg` (`brew install ffmpeg`), providing both `ffmpeg` and `ffprobe`. Optional - the job just skips videos (logging an error) if it's missing.
* `rellm deploy` (managing your own K8s cluster): `make` and `kubectl`. Optional - only needed if you use `rellm deploy`.

```bash
brew install jonlatane/rellm/rellm

rellm help # show subcommands for the bash launcher

# Either configure to use your own MinIO/Postgres (and thus not needing `createdb` or `docker`):
rellm environment # literally just: cat ~/.rellm. Contains database, MinIO, and optional TLS credentials.
rellm edit_environment # literally just: $EDITOR ~/.rellm. Edit those database, MinIO, and optional TLS 

# Or, create the examples. These are what will be auto-populated in ~/.rellm.
rellm local_db_create # Requires a local Postgres instance. literally just: createdb rellm_dev
rellm local_minio_start # literally "just": docker start rellm-dev-minio || docker run -d -p 9000:9000 -p 9090:9090 --name rellm-dev-minio -v $(MAKEFILE_DIR)/.minio-data:/data -e "MINIO_ROOT_USER=ROOTNAME" -e "MINIO_ROOT_PASSWORD=CHANGEME123" quay.io/minio/minio server /data --console-address ":9090"credentials.

# Launch the server (and its background jobs). HTTP on ports 80 and 8000, 27707 (gRPC), and HTTPS on 443 if TLS is configured.
rellm server_and_jobs

# Once the server is running (presumably in another tab, or the background, or a daemon),
# you can set up an admin user.
open http://localhost/

# In your browser, create a user account and remember your username.
# To give them admin permissions:
rellm set_permission my_admin_username admin on

brew upgrade jonlatane/rellm/rellm # Upgrade to the latest release.

# (DigitalOcean only for now) Create Postgres with 1GB storage, MinIO with 5GB storage, and a web-facing Rellm server (with a load balancer) in your DOKS (DigitalOcean Kubernetes) cluster with `make` and `kubectl`.
rellm deploy create_backend_data create_external_backend NAMESPACE=my-rellm-instance-namespace

# To tear that cluster deployment down again (kubectl deletes the whole namespace, and everything in it, at once):
kubectl delete namespace my-rellm-instance-namespace
```

### Linux: Self-updateable `.tar.bz2` with `arm64` and `amd64` binaries and launcher

Rather than figure out all the Linux repos' stuff, Rellm ships as Linux tarball with both `arm64` and `amd64` binaries, and a launcher (mirroring the Homebrew one) to choose the right archicture's binaries. It can also auto-delete unneeded binaries. You can run Rellm from either wherever you extract it, or install it to `~/.rellm-linux/` (which, along with the platform-agnostic env vars in `~/.rellm`, and any `$PATH`-setting you do yourself, are its only traces on your system).

Additional docs for the Rellm thin launcher can be found in [`docs/rellm_linux.sh`](https://github.com/JonLatane/rellm/blob/main/docs/rellm_linux.sh`) (which *is literally the launcher script that will become your `#{install_dir}/bin/rellm`*, if you wanna PR any changes).

Unlike the Homebrew distro, this is *straight up untested by me*. So please, submit issues or PRs.

#### 3 minute startup on Linux

**Prerequisites for your `$PATH`:** 

* Installation/Updates: `jq`, `curl`, `xargs`
* Postgres autoconfiguration: `createdb`, `dropdb`
* Docker/MinIO autoconfiguration: `docker`
* `convert_media_sizes` background job (images): ImageMagick (`apt install imagemagick`), providing either `magick` or the legacy `convert`+`identify` pair. Optional - the job just skips images (logging an error) if it's missing.
* `convert_media_sizes` background job (video): `ffmpeg` (`apt install ffmpeg`), providing both `ffmpeg` and `ffprobe`. Optional - the job just skips videos (logging an error) if it's missing.
* `rellm deploy` (managing your own K8s cluster): `make` and `kubectl`. Optional - only needed if you use `rellm deploy`.

```bash
# Get the package with curl/jq, and extract it. This is actually also what updater script does.
curl -s https://api.github.com/repos/jonlatane/rellm/releases/latest \
  | jq -r '.assets[] | select(.name | test("-linux\\.tar\\.bz2$")) | .browser_download_url' \
  | xargs curl -L -o rellm.tar.bz2
mkdir rellm && tar xjf rellm.tar.bz2 -C rellm && rm rellm.tar.bz2
cd rellm
./bin/rellm version

# Either just do this to run from wherever you extracted it:
export PATH=$PATH:$(pwd)/bin

# Or, to install to $HOME/.rellm-linux immediately:
./bin/rellm install
    # If you choose to install, this to might be also useful to add to your .profile/.zshrc/etc.:
    export PATH=$PATH:$HOME/.rellm-linux/bin

# Optional: tab-completion for rellm subcommands. Homebrew wires this up automatically;
# on Linux there's no package manager to hook into, so add ONE of these to your shell
# startup file yourself (works whether or not you ran `rellm install` above):
echo 'eval "$(rellm completion bash)"' >> ~/.bashrc   # bash
echo 'eval "$(rellm completion zsh)"' >> ~/.zshrc     # zsh

### The rest of setup is the same as for macOS:

rellm help # show subcommands for the bash launcher

# Either configure to use your own MinIO/Postgres (and thus not needing `createdb` or `docker`):
rellm environment # literally just: cat ~/.rellm. Contains database, MinIO, and optional TLS credentials.
rellm edit_environment # literally just: $EDITOR ~/.rellm. Edit those database, MinIO, and optional TLS 

# Or, create the examples. These are what will be auto-populated in ~/.rellm.
rellm local_db_create # Requires a local Postgres instance. literally just: createdb rellm_dev
rellm local_minio_start # literally "just": docker start rellm-dev-minio || docker run -d -p 9000:9000 -p 9090:9090 --name rellm-dev-minio -v $(MAKEFILE_DIR)/.minio-data:/data -e "MINIO_ROOT_USER=ROOTNAME" -e "MINIO_ROOT_PASSWORD=CHANGEME123" quay.io/minio/minio server /data --console-address ":9090"credentials.

# Launch the server (and its background jobs). HTTP on ports 80 and 8000, 27707 (gRPC), and HTTPS on 443 if TLS is configured.
rellm server_and_jobs

# Once the server is running (presumably in another tab, or the background, or a daemon),
# you can set up an admin user.
xdg-open http://localhost/

# In your browser, create a user account and remember your username.
# To give them admin permissions:
rellm set_permission my_admin_username admin on

# COST: $12.60/mo on DigitalOcean. (DigitalOcean only for now) Create Postgres with 1GB storage, MinIO with 5GB storage, and a web-facing Rellm server (with a load balancer) in your DOKS (DigitalOcean Kubernetes) cluster with `make` and `kubectl`.
rellm deploy create_backend_data create_external_backend NAMESPACE=my-rellm-instance-namespace

# To tear that cluster deployment down again (kubectl deletes the whole namespace, and everything in it, at once):
kubectl delete namespace my-rellm-instance-namespace
```

#### Install/self-update on Linux

Whereas Homebrew gives you updates via `brew`, the Linux version ships with an update script, again, a vibe-coded blend of `curl` and `jq`. Once you've gotten things running via the above guide, you may want to install. All these commands are [just a bash script you can/should look at before running them](https://github.com/JonLatane/rellm/blob/main/docs/rellm_linux.sh).

```bash
# If you want to self-update, you may want to:
rellm install # OPTIONAL. Copies your `rellm` directory to `~/.rellm-linux` Everything but "rellm update" works without installing.
rellm show_latest # Show the latest available release from GitHub.
rellm update # Updates you to the latest rellm release from GitHub.

# If you want to delete ~/.rellm and ~/.rellm-linux, you can always:
rellm uninstall
```

### DockerHub: Server and Preview Generator images

Rellm has an intuitive (helm-less) mechanism and conventions for templating Rellm server/Postgres/MinIO containers into Kubernetes namespaces. Helm-ification or other improvements, if "friendlily" documented, are very welcome.

[![DockerHub Server Images](https://img.shields.io/docker/v/jonlatane/rellm?label=dockerhub:rellm)](https://hub.docker.com/r/jonlatane/rellm/tags) [![DockerHub Preview Generator Images](https://img.shields.io/docker/v/jonlatane/rellm_preview_generator?label=dockerhub:rellm_preview_generator)](https://hub.docker.com/r/jonlatane/rellm_preview_generator/tags)

#### Deploying DockerHub images to Kubernetes from Homebrew/Linux (`rellm deploy`)

If you installed Rellm via [Homebrew](#macos-install-and-run-via-homebrew) or the [Linux package](#linux-self-updateable-tarbz2-with-arm64-and-amd64-binaries-and-launcher), both bundle a full copy of the `deploys/` directory - so `rellm deploy <targets...>` runs the exact same `kubectl`-powered `make` targets described in [Quick deploy to your own cluster](#quick-deploy-to-your-own-cluster) and [`deploys/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/README.md), without cloning this repo. For example: `rellm deploy create_backend_data create_external_backend NAMESPACE=my-rellm-instance-namespace`.

Tab-completion is available for both `rellm`'s own subcommands and `rellm deploy`'s targets. Homebrew wires this up automatically when you `brew install`; on Linux there's no package manager to hook into, so you'll want to add it yourself - see the "Optional: tab-completion" step of [3 minute startup on Linux](#3-minute-startup-on-linux).

#### Live (DigitalOcean Kubernetes/DOKS) deployments

Rellm's CI is set up to deploy the above Docker images as part of its build system. (In fact, it won't cut its GitHub/Homebrew/Linux releases until it deploys a canary build to [jonline.io](https://jonline.io).)

To set up a deployment yourself, see: [Quick deploy to your own cluster](#quick-deploy-to-your-own-cluster).

| Deployment                                                                                                    | Purpose                          | Federated Servers                                                                              | Links                                                                                                                                           | Deployment Version |
| ------------------------------------------------------------------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| [Jonline.io ![Jonline.io](https://jonline.io/info_shield?b6713cbc8)](https://jonline.io)                      | Flagship demo/informational site | [BullCity.Social (pinned), OakCity.Social (pinned), ATO.Band (pinned)](https://jonline.io/about?tab=federation) | [About](https://jonline.io/about), [Elm UI](https://jonline.io/elm/), [Tamagui/React UI](https://jonline.io/tamagui/), [Flutter UI](https://jonline.io/flutter/), [Protocol Docs](https://rellm.org/docs/protocol/)                | Development/Canary        |
| [Rellm.org ![Rellm.org](https://rellm.org/info_shield?b6713cbc8)](https://rellm.org)              | Flagship demo/informational site | TBD                                                                                                              | TBD                                                                                                                                                                                                                                    | Not yet deployed   |
| [BullCity.Social ![BullCity.Social](https://BullCity.Social/info_shield?b6713cbc8)](https://BullCity.Social/) | Durham, NC Community Page        | [OakCity.Social (pinned), ATO.Band (pinned)](https://bullcity.social/about?tab=federation)                      | [About](https://BullCity.Social/about), [Elm UI](https://BullCity.Social/elm/), [Tamagui/React UI](https://BullCity.Social/tamagui/), [Flutter UI](https://BullCity.Social/flutter/), [Protocol Docs](https://BullCity.Social/docs/protocol/) | Production         |
| [OakCity.Social  ![OakCity.Social](https://OakCity.Social/info_shield?b6713cbc8)](https://OakCity.Social/)     | Raleigh, NC Community Page       | [BullCity.Social (pinned), ATO.Band (pinned)](https://OakCity.Social/about?tab=federation)                      | [About](https://OakCity.Social/about), [Elm UI](https://OakCity.Social/elm/), [Tamagui/React UI](https://OakCity.Social/tamagui/), [Flutter UI](https://OakCity.Social/flutter/), [Protocol Docs](https://OakCity.Social/docs/protocol/)    | Production         |
| [ATO.Band ![ato.band](https://ato.band/info_shield?b6713cbc8)](https://ato.band/)     | Site for my band, Against The Odds | [BullCity.Social, OakCity.Social](https://ato.band/about?tab=federation), Facebook                      | [About](https://ato.band/about), [Elm UI](https://ato.band/elm/), [Tamagui/React UI](https://ato.band/tamagui/), [Flutter UI](https://ato.band/flutter/), [Protocol Docs](https://ato.band/docs/protocol/)    | Production         |

- [ Rellm  ](#-rellm--)
  - [Packages, Images \& Deployments](#packages-images--deployments)
    - [macOS: Install and Run via Homebrew](#macos-install-and-run-via-homebrew)
      - [2 minute startup with Homebrew](#2-minute-startup-with-homebrew)
    - [Linux: Self-updateable `.tar.bz2` with `arm64` and `amd64` binaries and launcher](#linux-self-updateable-tarbz2-with-arm64-and-amd64-binaries-and-launcher)
      - [3 minute startup on Linux](#3-minute-startup-on-linux)
      - [Install/self-update on Linux](#installself-update-on-linux)
    - [DockerHub: Server and Preview Generator images](#dockerhub-server-and-preview-generator-images)
      - [Deploying DockerHub images to Kubernetes from Homebrew/Linux (`rellm deploy`)](#deploying-dockerhub-images-to-kubernetes-from-homebrewlinux-rellm-deploy)
      - [Live (DigitalOcean Kubernetes/DOKS) deployments](#live-digitalocean-kubernetesdoks-deployments)
  - [What is Rellm?](#what-is-rellm)
    - [Why Rellm vs. Mastodon/Bluesky?](#why-rellm-vs-mastodonbluesky)
      - [Rellm as a protocol vs. ActivityPub](#rellm-as-a-protocol-vs-activitypub)
      - [Rellm as a protocol vs. Bluesky/AT Protocol](#rellm-as-a-protocol-vs-blueskyat-protocol)
    - [Why *not* Rellm?](#why-not-rellm)
  - [Federation \& Synchronization Features](#federation--synchronization-features)
    - [Inter-Server Federation](#inter-server-federation)
      - [Federated Servers](#federated-servers)
      - [Cross-Protocol Federation](#cross-protocol-federation)
        - [Mastodon/ActivityPub](#mastodonactivitypub)
        - [BlueSky/AT Protocol](#blueskyat-protocol)
      - [Federated Profiles](#federated-profiles)
      - [Federated Browsing](#federated-browsing)
      - [Federated Messaging](#federated-messaging)
    - [Synchronization with Outside Servers](#synchronization-with-outside-servers)
      - [Sync Sources](#sync-sources)
        - [iCal](#ical)
        - [RSS](#rss)
        - [Atom](#atom)
      - [Sync Destinations](#sync-destinations)
        - [Facebook](#facebook)
        - [Instagram](#instagram)
        - [Mastodon](#mastodon)
        - [Bluesky](#bluesky)
        - [X (Twitter)](#x-twitter)
        - [Threads](#threads)
  - [Cloud/Cluster-Friendly Features](#cloudcluster-friendly-features)
    - [Integrated Deployment System](#integrated-deployment-system)
    - [Cluster-Agnostic Shared Resource Management](#cluster-agnostic-shared-resource-management)
  - [Single-Instance Features](#single-instance-features)
    - [Rellm Identifiers: Usernames, Group Names, and IDs](#rellm-identifiers-usernames-group-names-and-ids)
    - [People, Followers and Friends](#people-followers-and-friends)
    - [Groups and Memberships](#groups-and-memberships)
    - [Media](#media)
    - [AI Providers](#ai-providers)
      - [Gemini](#gemini)
      - [OpenAI](#openai)
      - [Anthropic](#anthropic)
      - [DigitalOcean](#digitalocean)
    - [Posts](#posts)
      - [GroupPost](#grouppost)
    - [Events](#events)
    - [Messages](#messages)
    - [Potential future features](#potential-future-features)
    - [Delightful Federation](#delightful-federation)
    - [Protocol Documentation](#protocol-documentation)
  - [Project Components](#project-components)
    - [Documentation](#documentation)
    - [gRPC APIs](#grpc-apis)
    - [Architecture/Deployment Management](#architecturedeployment-management)
    - [Rust Backend](#rust-backend)
    - [Frontends](#frontends)
      - [Elm Frontend](#elm-frontend)
      - [Tamagui/React/Next.js Frontend](#tamaguireactnextjs-frontend)
      - [Flutter Frontend (Deprecated/Frozen for Reference)](#flutter-frontend-deprecatedfrozen-for-reference)
  - [Quick deploy to your own cluster](#quick-deploy-to-your-own-cluster)
    - [Deployment management: domains and TLS certs; deploying multiple `rellm` instances to different K8s namespaces in the same cluster; and cross-namespace load balancing with Traefik](#deployment-management-domains-and-tls-certs-deploying-multiple-rellm-instances-to-different-k8s-namespaces-in-the-same-cluster-and-cross-namespace-load-balancing-with-traefik)
  - [Motivations](#motivations)

## What is Rellm?

Broadly speaking, Rellm is something of an "internet philosophy." It's my (Jon's) philosophy. It's a generally anti-capitalist tech approach that has a few perhaps obvious opinions on everything from user data privacy expectations, to cost of servers, through CI/CD, the BE, API design, user expectations for transparent permissions/moderation/visibility on things like People, Media, Groups, Posts, and Events, etc. Conveniently, things that meet my (Jon's) requirements for these these things can be described as "Rellm CI/CD,", "Rellm API Design,", "Rellm Events," and so forth.

As a more traditional market product, Rellm is a network of, and a protocol for, social networks that meets my (Jon's) expectations of usability, transparency, and fairness. It's designed to scale as well as Mastodon or better, but really, it aims to be something more like [Plex](https://www.plex.tv/), but as a social network released under the [AGPL](https://fossa.com/blog/open-source-software-licenses-101-agpl-license/) (and also, Kubernetes/LetsEncrypt/CertManager-friendly). Use cases include:

- Neighborhoods, communities, or cities
- (Ex-)Coworkers wanting a private channel to chat
- Run/bike/etc. clubs
- App user groups
- Online game clans
- Board game groups
- D&D parties
- Local concert listings
- Event venue calendars

The core model of Rellm is that *each of these communities is run as its own Rellm instance*. Each of these instances and their data are literally *owned* by the organization (or a chosen "IT admin person" and/or "moderation team" for it). Finally, the same person's *accounts on all of these instances can be federated* (if the user chooses, and dependent upon server configurations and permissions, of course). Federation is simply a means to let, say, a user, Jeff, see their D&D DM also knows the guy from run club who left his wallet, *even if Jeff and the DM are not friends on the run club network*, but *only if the DM chooses* to federate their identity across both those networks.

One way to think of Rellm is as social media meets the email server model (I use Gmail, you use your ISP's email, we can still talk to each other), with a bit of the ListServ model too (it's *very* easy to set up a neighborhood Rellm instance, Posts function effectively identically to ListServ messages, and Events are basically just a nice extra feature ListServ doesn't have).

Another way to think of Rellm is that it's like Slack or Discord, except instead of messages/channels/voice chats, it's just for Posts and Events. And your Rellm instance is code you can actually see running on equipment you own, not proprietary code running on a corporation's servers.

A core goal is to make Rellm dogshit easy (🐕💩EZ) for anyone else to deploy to any Kubernetes provider of their choosing (and to fork and modify). It's also (optimistically) simple and straightforward enough to serve as a starter for many projects, so long as they retain the [AGPL license Rellm is released under](https://github.com/JonLatane/rellm/blob/main/LICENSE.md). All you need is a Kubernetes (k8s) cluster, `git`, `kubectl`, `make`, and a few minutes to get the [prebuilt image](https://hub.docker.com/repository/docker/jonlatane/rellm) up and running. This very document also has instructions for a [2 minute startup with Homebrew](#2-minute-startup-with-homebrew) and [3 minute startup on Linux](#3-minute-startup-on-linux).


In a perfect Rellm universe, every local business with a sip 'n' sketch, open mic, trivia night, run/bike club, etc.; every arts council, parks & rec department, library, etc. could run a Rellm instance on their own hardware or from any number of providers (because it's very cheap to host lots of Rellm instances on a cloud, by design) for a cost of $20-50/year from a provider, or for free on their own servers. Members of these communities could sign up only with the ones they want, and view events/posts where they want, when they want. Those community members don't need to share emails or phone numbers to do anything on these communities. Moderation is done by people working at the businesses/organizations. No one can become a billionaire running it, but also, users can participate in all these communities online without their data becoming the property of some billionaire.

### Why Rellm vs. Mastodon/Bluesky?

Rellm as a protocol is essentially a superset of most of what people use ActivityPub and ATProto for, with a lot of other things that they *should* have had. It notably does *not* have hashtags, which I at the moment consider a good thing. It does, however, support full-text search (backed by the Postgres standard feature).

Rellm, as a Rust BE, is *blazing fast* compared to any Rails BE. And being written in Rust, memory safety is built-in, and entire classes of backend errors that arise from using dynamic/GC'ed languages simply don't compile and thus go away (once you've written it so it *will* compile, as a developer). It speaks comfortably with external data sources like iCal, networks like Facebook, Instagram, X (Twitter), *just as well* as it interoperates with Mastodon/Bluesky instances. And Rellm is designed to be easy to deploy to any arbitrary Kubernetes provider, or in virtually any "home cluster" situation you might concoct for yourself.

Rellm's Elm FE is similarly blazing fast, and Elm as a language allows intuitive, reliable web UIs in a way that nothing else out there really does (maybe Gleam). It similarly offers Mastodon/Bluesky interoperability at a level that, well, would be *painful or impossible* to implement without the safety of Elm, no matter how many humans or AI agents you throw at the problem.

- Rellm supports Events as a first-class type. Others don't.
- Rellm supports a unique Messaging model that means (with the [Stalwart integration](deploys/email/README.md) set up) the user at `jonline.io/jon` can be emailed at `jon@jonline.io`; and, that user has it set up, they can receive VAPID (web push) notifications of said emails and messages from other users.
- Rellm servers offer admins a huge amount of configurability that can effectively make it a site and CRM for your business's run/bike/trivia clubs, your band/chorus/dance groups's site, and more, with custom color schemes, custom tab layouts, pseudonyms for posts and events (like "twaddles" or "shows"), and much more.
- Rellm's UI and APIs are designed to let users browse federated User Profiles, Groups, Posts and Events with ease in a way not supported in other "fediverse" apps.
- Rellm servers serve up multiple UIs as well as their own protocol docs, making it easy to grab an arbitrary agent and point it at Rellm.
- [Rellm Protocol Docs](https://rellm.org/docs/protocol) are arguably *far clearer* and *easier to use*, be you human or AI, than [ActivityPub Protocol Docs](https://www.w3.org/TR/activitypub/). More comparison is below.
- Rellm's server images are structured so you only need one LoadBalancer (the things you typically pay for) per deploy/website, and really only one web-facing container (though it defaults to 2) per deploy.
  - Within the containers themselves, everything is handled by a single Rust BE binary. No scripting runtime. So containers are small, even with useful Linux tools like `psql` and `grpcurl` built in. They start *really fast*, and Kubernetes failovers work very smoothly.
- Rellm deploy scripts are designed to be so easy to deploy to Kubernetess you can be braindead and get it up and running for your website. Further, it's all just `Makefile`s and `kubectl` commands (though maybe that's a con for the reader 😁).

The goal of all this is to make it as easy as possible for local businesses to:

- Engage with customers on a platform customers enjoy.
- Use Rellm to share information about customers between each other, in a way customers can easily understand and consent to, without a central corporation being involved.
  - Example: make it easy for Kathy to share her band's show with the folks at her yoga studio, by cross-posting it to her yoga studio profile

#### Rellm as a protocol vs. ActivityPub

Rellm is also a protocol, much like ActivityPub. It's worth skimming both the [ActivityPub Protocol Docs](https://www.w3.org/TR/activitypub/) and the [Rellm Protocol Docs](https://rellm.org/docs/protocol), but this is a brief breakdown.

Notably, while ActivityPub specifies a server-to-server federation protocol, Rellm simply lets servers "recommend" other servers by hostname, with the "federation" done on the client side by communicating with the recommended servers based on user authorization. (Yes, this could barely defined as "federation" at all - but it's cheaper and effectively the same to users. The Rellm protocol simply calls this [delightful federation](https://rellm.org/docs/protocol#delightful-federation).)

While ActivityPub is defined using HTTP(S) and JSON, Rellm is defined with gRPC (on port 27707, with optional TLS), using HTTP(S) for media and CDN-based host negotiation only (no JSON, anywhere). Broadly speaking, Rellm may be called "more opinionated" than ActivityPub as a social networking protocol, and covers more things than just social activity (including things like user-facing server configuration data, privacy policy, etc.).

Whereas ActivityPub has a flexible Activity model capable of holding varied metadata, Rellm's API definitions deliberately avoid allowing for metadata, and focus on statically-typed, specific models for Posts and Events. The Rellm data model is designed using composition, with Events' titles, descriptions, moderation, etc. belonging to a Post owned by them, over inheritance (i.e. making Event "extend" Post in OOP). Rellm leverages this to implement visibility and moderation controls for Posts and Events across the system all in one place.

In addition to Users, Posts, and Events, which could all be "described" by ActivityPub's specification, Rellm also has Media (designed to leverage external CDNs), Groups, Server Configuration, and moderation/visibility/permission management across everything as a first-class citizen.

Put differently: Rellm's federation *mechanism* is strictly simpler than ActivityPub's (no server-to-server delivery protocol at all - see [Delightful Federation](#delightful-federation)), while its *object model* covers a meaningful superset of what a typical ActivityPub app implements - first-class Events (with recurring Occasions), Groups (with membership/moderation), and Media (as its own visibility-controlled entity), alongside Users/Posts. So it's fair to call Rellm roughly isomorphic to a statically-typed, non-extensible *profile* of ActivityPub's actor/object vocabulary, expanded with a few practical types the base spec leaves to extensions - but not to ActivityPub's federation protocol itself, which Rellm deliberately doesn't replicate.

The hope is to build more useful business objects - yes, your boring SalesForce/NetSuite/SAP type stuff - into this social protocol. So Rellm Payments, Products, Subscriptions, and who knows what else could, eventually, be gradually implemented atop the Rellm protocol, with all the same clear, concise, documentation, cross-language portability, and other benefits it offers.

All this is to say: it should be pretty straightforward to create, say, Ruby bindings for Rellm, and use them in Mastodon to make it work as a no-Events-support, no-Media-support Rellm instance. Or vice versa. This is back burner research, though. Get in contact if you're interested in contributing/learning to do this type of work!

#### Rellm as a protocol vs. Bluesky/AT Protocol

Bluesky's AT Protocol looks architecturally nothing like Rellm (or ActivityPub, for that matter): identity and data live on independent Personal Data Servers (PDSes), which get crawled by Relays into a global firehose, which is then indexed and ranked into feeds by separate AppViews (Bluesky's own app being just one of potentially many). Nothing in Rellm has an equivalent of this data/aggregation/ranking split - a Rellm server is identity, storage, and API all in one, much closer to a Mastodon instance (or a plain web app) than to a PDS.

Rellm's [Cross-Protocol Federation](#cross-protocol-federation) reads Bluesky content by simply calling the same public AT Protocol endpoints (`com.atproto.server.createSession`, `app.bsky.feed.getTimeline`) any Bluesky client would, translated client-side into Rellm's `Post` shape - it doesn't, and doesn't need to, participate in the PDS/Relay/AppView network itself.

### Why *not* Rellm?

- It's definitely not as big as the others yet.
- 

## Federation & Synchronization Features

### Inter-Server Federation

Whereas ActivityPub servers federate by pushing Activities directly to each other's inboxes (authenticated via HTTP Signatures), and Bluesky (AT Protocol) federates via independent Personal Data Servers that get crawled by Relays and re-indexed by AppViews, two Rellm servers never talk to each other at all. A server only ever *recommends* other servers by hostname; it's always the client that calls each recommended server's own client-facing API directly and merges the results - see [Federated Servers](#federated-servers) below, and [Cross-Protocol Federation](#cross-protocol-federation), which reads Mastodon/Bluesky content into a Rellm client the exact same way. The one place Rellm's own backend does initiate server-to-server calls is [Sync Destinations](#sync-destinations) - pushing a user's own content *out* to other platforms on their behalf, which needs the server (not a browser tab) to hold onto that user's long-lived credentials for those platforms.

#### Federated Servers

Rellm servers can recommend other servers to clients via the `federation_info` field (a [`FederationInfo` message](https://rellm.org/docs/protocol#rellm-FederationInfo)) in [`ServerConfiguration`](https://rellm.org/docs/protocol#rellm-ServerConfiguration). Clients can use this information to discover other servers, or users can add new servers manually. Note that, at least for web clients, this means everything is subject to CORS. In the future, Rellm will allow CORS to be configured in a "strict" mode, so someone else's Rellm server cannot be used to access your server's data unless you explicitly allow it.

#### Cross-Protocol Federation

Rellm can also translate content *from* other federated protocols into its own [`Post`](https://rellm.org/docs/protocol#rellm-Post) model, entirely client-side - no Rellm server ever proxies or bridges this data, it's the same "client does the merging" pattern as [Federated Servers](#federated-servers) above, just reaching across a protocol boundary instead of a Rellm-to-Rellm one. It's also one-directional (reading in, not posting out) - publishing a Rellm Post *to* Mastodon or Bluesky is instead handled by [Sync Destinations](#sync-destinations).

##### Mastodon/ActivityPub

Any Mastodon instance's local public timeline can be browsed with no account or admin configuration at all, since it's already a public, unauthenticated REST endpoint - see [Federated Browsing](#federated-browsing). Connecting an actual Mastodon *account* (to eventually post/reply as yourself, or see your own home timeline) is a heavier flow, since a server admin first has to register an OAuth app on that instance (`FederationInfo.mastodon_servers`, a [`MastodonServer`](https://rellm.org/docs/protocol#rellm-MastodonServer)) - unlike Facebook or X, Mastodon has no single central platform to register one app against for every instance at once.

##### BlueSky/AT Protocol

Unlike Mastodon, AT Protocol has no "local instance timeline" concept a client could browse anonymously - every Personal Data Server only ever serves its own users' own data. So Bluesky cross-protocol federation always requires a connected account: a handle plus an [App Password](https://bsky.app/settings/app-passwords) (not OAuth - Bluesky has no per-app registration step the way Mastodon/Facebook/X do), showing that account's own home timeline rather than a public firehose.

#### Federated Profiles

Rellm users can federate with users on any other Rellm server. This works by two-way verification: for example, Jon has the user [`jonline.io/jon`](https://jonline.io/jon), [`oakcity.social/jon`](https://oakcity.social/jon), and [`bullcity.social/jon`](https://bullcity.social/jon) associated with one another. The UI will only show federated profiles if *both* user profiles have federated with one another.

This mechanism also allows users to link multiple profiles on the same server together. For instance, [`bullcity.social/jon`](https://bullcity.social/jon) and `bullcity.social/openmic` are linked together, but `bullcity.social/openmic` isn't linked to [`jonline.io/jon`](https://jonline.io/jon) or [`oakcity.social/jon`](https://oakcity.social/jon).

Federated profiles are managed via the `federated_profiles` field (a `repeated` [`FederatedAccount`](https://rellm.org/docs/protocol#rellm-FederatedAccount)) on the [`User`](https://rellm.org/docs/protocol#rellm-User) message.

#### Federated Browsing

Rellm's protocols and UI are designed to work together to present a seamless UX for content from many types of communities. Users can add/remove servers in a way that gives them control, transparency and trust. Meanwhile, server owners get extreme customization and useful integrations with social media platforms.

#### Federated Messaging

Rellm's Elm Messaging UI is generally a multi-server federated messenger. The main limitation is that it can only receive push notifications from one server. (This could be changed with VAPID key sharing, but is part of the VAPID protocol.)

#### Federated Markets

The Elm `/market` page can show more than one server's Market side by side: the browsed server's own (always first) plus any other connected, enabled server whose `ServerConfiguration.market_settings.enabled` is set (in Accounts panel order after that) — the public, non-secret "is this server's Market open" signal, unlike `stripe_config` itself, which stays Admin-only. Each section is fully independent: it lists that server's own [`MarketProduct`](https://rellm.org/docs/protocol#rellm-MarketProduct)s and shows product-management controls only if the current user is actually an Admin *on that server*.

Unlike Federated Browsing/Profiles/Messaging above, buying is never seamless across servers — Market is the one place a user must always transact with the target site directly. A product tile for the browsed server links to its own in-app product page as usual, but a tile for any *other* server links straight to that server's own `https://{host}/market/product/{id}` (a real page navigation, not client-side routing), since [`MakeMarketPurchase`](https://rellm.org/docs/protocol#grpc-api-MakeMarketPurchase) starts a Stripe Checkout Session scoped to whichever server the buyer is actually authenticated against, and Stripe's own `success_url`/`cancel_url` redirect back to that same server when payment completes.

### Synchronization with Outside Servers

While Federation is a first-class feature of Rellm, it also supports synchronization with other fediverse platforms as well as other less-open platforms. All API keys for external services are stored in [`ServerConfiguration`](https://rellm.org/docs/protocol#rellm-ServerConfiguration)'s `federation_info`.

#### Sync Sources

A [`SyncSource`](https://rellm.org/docs/protocol#rellm-SyncSource) is a server-owned external origin to pull [`Post`](https://rellm.org/docs/protocol#rellm-Post)s in from, via a `oneof configuration` naming which source type it is: an iCal subscription URL (creates/updates [`Event`](https://rellm.org/docs/protocol#rellm-Event)s and [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion)s), or an RSS/Atom subscription URL (creates/updates plain [`Post`](https://rellm.org/docs/protocol#rellm-Post)s). Every kind of synced content is tagged via its own `Post.sync_source` - an [`Event`](https://rellm.org/docs/protocol#rellm-Event)'s own Post, each of its [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion)s' own Post, or a plain synced Post - since a single source can back many synced Posts but each Post has at most one source it came from. A background job re-pulls each source on its own configurable interval.

Sources are managed via [`GetSyncSources`](https://rellm.org/docs/protocol#grpc-api-GetSyncSources), [`CreateSyncSource`](https://rellm.org/docs/protocol#grpc-api-CreateSyncSource) (requires `SYNC_EVENTS_FROM_ICS`/`SYNC_POSTS_FROM_RSS`/`SYNC_POSTS_FROM_ATOM` - whichever matches the source's own configuration - or Admin), [`UpdateSyncSource`](https://rellm.org/docs/protocol#grpc-api-UpdateSyncSource), and [`DeleteSyncSource`](https://rellm.org/docs/protocol#grpc-api-DeleteSyncSource).

See also: [Sync Destinations](#sync-destinations)

##### iCal

`configuration.ics_subscription_url` is a plain iCal (`.ics`) subscription URL. The background job fetches and parses it on each sync, creating/updating one [`Event`](https://rellm.org/docs/protocol#rellm-Event) (and one [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion) per occurrence) per iCal `VEVENT`, recomputing `event_count`/`occasion_count`. No auth/credentials are supported yet - only public iCal URLs.

Rellm also serves its own Events back out as an ICS feed (`GET /calendar.ics`, optionally `?user_id={id}`) - the reverse direction of a `SyncSource`'s own subscription, for others to subscribe to a Rellm server or user.

##### RSS

`configuration.rss_subscription_url` is a plain RSS 2.0 subscription URL. The background job fetches and parses it on each sync, creating/updating one plain [`Post`](https://rellm.org/docs/protocol#rellm-Post) per RSS item, recomputing `post_count`. Unlike iCal, an item that stops appearing in the feed is left alone rather than pruned - RSS feeds are commonly truncated to their most recent N items by the publisher, so "no longer in the feed" doesn't mean "was retracted". No auth/credentials are supported yet - only public RSS URLs.

Rellm also serves its own Posts back out as an RSS feed (`GET /rss.xml`, optionally `?user_id={id}`) - the reverse direction of a `SyncSource`'s own subscription, for other feed readers to subscribe to a Rellm server or user.

##### Atom

`configuration.atom_subscription_url` is a plain Atom subscription URL, behaving identically to RSS (above) - one plain [`Post`](https://rellm.org/docs/protocol#rellm-Post) per entry, recomputing `post_count`, missing entries left alone rather than pruned. RSS and Atom feeds are parsed via the same underlying library into one unified shape, so both formats share this exact behavior - pick whichever a given source actually publishes.

Rellm also serves its own Posts back out as an Atom feed (`GET /atom.xml`, optionally `?user_id={id}`) - the reverse direction of a `SyncSource`'s own subscription, for other feed readers to subscribe to a Rellm server or user.

#### Sync Destinations

A [`SyncDestination`](https://rellm.org/docs/protocol#rellm-SyncDestination) is a user-owned external target to push [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion)s and [`Post`](https://rellm.org/docs/protocol#rellm-Post)s out to, via a `oneof configuration` naming which platform it is. This is a many-to-many relationship: it's each [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion) or [`Post`](https://rellm.org/docs/protocol#rellm-Post) (not, say, the parent [`Event`](https://rellm.org/docs/protocol#rellm-Event)) that syncs out, and each may push to several destinations at once, tracked per-destination via the repeated `Occasion.sync_destinations`/`Post.sync_destinations` (each a [`SyncDestinationStatus`](https://rellm.org/docs/protocol#rellm-SyncDestinationStatus), carrying the destination's resulting post ID/URL and last-synced time). Destinations are pushed to on demand rather than synced in bulk on an interval.

Destinations are managed via the [`GetSyncDestinations`](https://rellm.org/docs/protocol#grpc-api-GetSyncDestinations), [`CreateSyncDestination`](https://rellm.org/docs/protocol#grpc-api-CreateSyncDestination), [`UpdateSyncDestination`](https://rellm.org/docs/protocol#grpc-api-UpdateSyncDestination), and [`DeleteSyncDestination`](https://rellm.org/docs/protocol#grpc-api-DeleteSyncDestination) RPCs - each gated on the `SYNC_EVENTS_TO_*`/`SYNC_POSTS_TO_*` permission pair matching the destination's own platform (or Admin; see each platform below). Actually syncing (or un-syncing) a given [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion) or [`Post`](https://rellm.org/docs/protocol#rellm-Post) to a destination is a separate step, via [`SyncOccasion`](https://rellm.org/docs/protocol#grpc-api-SyncOccasion)/[`DeleteOccasionSyncDestination`](https://rellm.org/docs/protocol#grpc-api-DeleteOccasionSyncDestination) and [`SyncPost`](https://rellm.org/docs/protocol#grpc-api-SyncPost)/[`DeletePostSyncDestination`](https://rellm.org/docs/protocol#grpc-api-DeletePostSyncDestination).

See also: [Sync Sources](#sync-sources)

##### Facebook

`configuration.facebook_page` (a [`FacebookPage`](https://rellm.org/docs/protocol#rellm-FacebookPage)) is a connected Facebook Page. Connecting one requires a short-lived user access token from client-side Facebook Login, which the server exchanges for a long-lived Page access token. Gated on `SYNC_EVENTS_TO_FACEBOOK`/`SYNC_POSTS_TO_FACEBOOK`.

##### Instagram

`configuration.instagram_account` (an [`InstagramAccount`](https://rellm.org/docs/protocol#rellm-InstagramAccount)) is a connected Instagram Business/Creator account. Instagram posting is only possible for an account linked to a Facebook Page, so connecting one reuses the exact same Facebook Login flow/app credentials as Facebook above - the server exchanges the token for the chosen Page's access token, then looks up that Page's linked Instagram Business account. Unlike Facebook, Instagram's Graph API has no text-only post type; syncing a [`Post`](https://rellm.org/docs/protocol#rellm-Post)/[`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion) with no attached media fails. Gated on `SYNC_EVENTS_TO_INSTAGRAM`/`SYNC_POSTS_TO_INSTAGRAM`.

##### Mastodon

`configuration.mastodon_account` (a [`MastodonAccount`](https://rellm.org/docs/protocol#rellm-MastodonAccount)) is a connected Mastodon account, on any instance the user names - there's no single app to register the way Facebook/Instagram have one, so connecting one is a user-pasted Personal Access Token (generated on the user's own instance under Preferences > Development) rather than an OAuth popup. Gated on `SYNC_EVENTS_TO_MASTODON`/`SYNC_POSTS_TO_MASTODON`.

##### Bluesky

`configuration.bluesky_account` (a [`BlueskyAccount`](https://rellm.org/docs/protocol#rellm-BlueskyAccount)) is a connected Bluesky (AT Protocol) account. Connecting one is a user-supplied "App Password" (generated at Settings > App Passwords - not the account's main password) rather than an OAuth popup. Gated on `SYNC_EVENTS_TO_BLUESKY`/`SYNC_POSTS_TO_BLUESKY`.

##### X (Twitter)

`configuration.x_twitter_account` (an [`XTwitterAccount`](https://rellm.org/docs/protocol#rellm-XTwitterAccount)) is reserved for a connected X account, but **not yet functional** - this requires a registered X Developer App (`FederationInfo.x_twitter_auth_config`), so every RPC touching an [`XTwitterAccount`](https://rellm.org/docs/protocol#rellm-XTwitterAccount) destination currently fails. Gated on `SYNC_EVENTS_TO_X_TWITTER`/`SYNC_POSTS_TO_X_TWITTER` once functional.

##### Threads

`configuration.threads_account` (a [`ThreadsAccount`](https://rellm.org/docs/protocol#rellm-ThreadsAccount)) is a connected Threads account. The Threads API is a product added to a server's *existing* Facebook App rather than a separately-registered app, but its OAuth flow is otherwise its own: authorization happens at threads.net (not facebook.com) using `response_type=code` rather than Facebook's implicit `response_type=token`, with no "choose a Page" step - it directly authorizes the user's own Threads account. Unlike Instagram, Threads supports text-only posts. Gated on `SYNC_EVENTS_TO_THREADS`/`SYNC_POSTS_TO_THREADS`.

## Cloud/Cluster-Friendly Features

### Integrated Deployment System

Both Rellm's Homebrew and Linux packages ship with the same `make` and `kubectl`-based deployment system that Rellm's CI uses. So deploying is as easy as:

```bash
# macOS: 1-line install
brew install jonlatane/rellm/rellm

# Linux: Tarball install
# Get the package with curl/jq, and extract it. This is actually also what updater script does.
curl -s https://api.github.com/repos/jonlatane/rellm/releases/latest \
  | jq -r '.assets[] | select(.name | test("-linux\\.tar\\.bz2$")) | .browser_download_url' \
  | xargs curl -L -o rellm.tar.bz2
mkdir rellm && tar xjf rellm.tar.bz2 -C rellm && rm rellm.tar.bz2
cd rellm
./bin/rellm version

# Deploy your BE
# COST: $12.60/mo on DigitalOcean. $0.60 for data and $12 for a load balancer. 
rellm deploy create_backend_data create_external_backend NAMESPACE=my-rellm-instance-namespace

# Get the IP for your backend. It may read <none> until DigitalOcean/DOKS/K8s finishes LoadBalancer setup for your instance.
rellm deploy get_backend_external_ip NAMESPACE=my-rellm-instance-namespace
```

From here, you can simply point your DNS for whatever domain at the LoadBalancer that should appear in your DigitalOcean dashboard.

Rellm also supports running *many* sites in a single Kubernetes (or other) cluster (which can be a single node/machine, quite cheap), with a Traefik ingress. for an effective cost of machine cost ($24/mo for 2vCPU/4GB/80GB on DigitalOcean) + $12/mo for a Traefik LoadBalancer + $0.60/mo per site. Because everything is basically one of two images, (4-5 when deploying new versions), this scales to many sites easily, even on minimal hardware. This can, of course, introduce performance constraints that may require resource management.

### Cluster-Agnostic Shared Resource Management

Rellms's shared resource management works even if you're not using Kubernetes, and instead using Docker VMs. That's because, rather than relying on Kubernetes leases, it's built into the protocol itself, based on two simply RPCs: `LockClusterResource` and `FreeClusterResource`.

Among other things, Rellm leverages this locking behavior to enable Chrome screenshot generation for 4+ different sites, on a 2vCPU/4GB box, using a `BROWSER` resource.

Rellm's bespoke resource management allows it to actually address the reesources in Rellm that may affect overall cluster performance at scale.

## Single-Instance Features 

All of Rellm's features should be pretty familiar to most social media users. Notably, in both its web and Flutter UIs, Rellm is designed to present "My Media" as a top-level feature and let users delete and manage Media visibility independently of Posts, Events, Groups or anything else.

### Rellm Identifiers: Usernames, Group Names, and IDs

A key point of contention in the Fediverse is the notion of universal usernames and IDs. Rellm also supports Groups and Group Names (which work much like subreddits or Facebook groups). There's a lot of complex implementations around this in Mastodon and elsewhere. Since Rellm's protocols do not specify anything about server-to-server communication, none of that stuff is really necessary in the Rellm approach at all! At a high level, Rellm Usernames, Group Names, and IDs look like a mix between URLs and email addresses. An important feature of both Rellm Usernames and IDs is that they do not change when URL-encoded.

For instance: I can claim [jonline.io/jon](https://jonline.io/jon), [bullcity.social/jon](https://bullcity.social/jon), and [oakcity.social/jon](https://oakcity.social/jon) for myself. But if you decide to start an instance at [febreze.lol/jon](https://febreze.lol/jon) and I want to make an account and share with you (I absolutely would!), I'll just have to register as [febreze.lol/rellm-jon](https://febreze.lol/rellm-jon) or my username of choice to interact on there. (But, in the future, I will be able to interlink all 4 of these profiles to make them appear as verified alternate identities across the servers!)

**Rellm Usernames** are, essentially, a link to a profile. Rellm gives the top-level resource names to users; i.e., user `bob123` on [jonline.io](https://jonline.io) can be found at [jonline.io/bob123](https://jonline.io/bob123). Users can change their usernames, but User IDs are permanent (unless the server administration changes the ID offset; see below for details.) [The few usernames you can't use on Rellm are enumerated in this Rust source.](https://github.com/JonLatane/rellm/blob/main/backend/src/rpcs/validations/validate_fields.rs)

Example Rellm usernames:

- [jonline.io/jon](https://jonline.io/jon): A user on [jonline.io](https://jonline.io).
- [bullcity.social/jon](https://bullcity.social/jon): A user on [bullcity.social](https://bullcity.social).
- [jonline.io/jon@bullcity.social](https://jonline.io/jon@bullcity.social): A view of [bullcity.social/jon](https://bullcity.social/jon) when using [jonline.io](https://jonline.io). (Note that [bullcity.social](https://bullcity.social) must permit [jonline.io](https://jonline.io) via CORS for loading to work.)

**Rellm Group Names** work much like usernames, but for groups. They are automatically derived from the actual group name (they are the field `Group.shortname`, derived from `Group.name` by removing non-word characters).

Example Rellm Group Names:

- [jonline.io/g/Fitness](https://jonline.io/g/Fitness): A group on [jonline.io](https://jonline.io).
- [bullcity.social/g/Running](https://bullcity.social/g/Running): A group on [bullcity.social](https://bullcity.social).
- [jonline.io/g/Running@bullcity.social](https://jonline.io/g/Running@bullcity.social) - a view of [bullcity.social/g/Running](https://bullcity.social/g/Running) when using [jonline.io](https://jonline.io). (Note that [bullcity.social](https://bullcity.social) must permit [jonline.io](https://jonline.io) via CORS for loading to work.)

**Rellm IDs** are numerical IDs for any entity type on a server. We might say: *in the context of Jonline.io*, Post ID `T6S8eoDmmtb` would be expected to be found at [jonline.io/post/T6S8eoDmmtb](https://jonline.io/post/T6S8eoDmmtb). (Note that the numerical portion of the ID is literally just a 64-bit integer encoded with base58 and a server-configurable offset. The best reference for how "Rellm ID Marshaling" works would be [these <90 lines, including test coverage, of Rust code.](https://github.com/JonLatane/rellm/blob/main/backend/src/marshaling/id_marshaling.rs))

Example Rellm IDs:

- [jonline.io/post/T6S8eoDmmtb](https://jonline.io/post/T6S8eoDmmtb): A Post on [jonline.io](https://jonline.io).
- [bullcity.social/post/2g1j95Bw5gB](https://bullcity.social/post/2g1j95Bw5gB): A Post on [bullcity.social](https://bullcity.social).
- [jonline.io/post/2g1j95Bw5gB@bullcity.social](https://jonline.io/post/T6S8eoDmmtb): A view of [bullcity.social/post/2g1j95Bw5gB](https://bullcity.social/post/2g1j95Bw5gB) when using [jonline.io](https://jonline.io). (Note that [bullcity.social](https://bullcity.social) must permit [jonline.io](https://jonline.io) via CORS for loading to work.)
- [bullcity.social/event/4rAfoSKAuJo](https://bullcity.social/event/4rAfoSKAuJo): An Event on [bullcity.social](https://bullcity.social).
- [jonline.io/event/4rAfoSKAuJo@bullcity.social](https://jonline.io/event/4rAfoSKAuJo@bullcity.social) - a view of [bullcity.social/event/4rAfoSKAuJo](https://bullcity.social/event/4rAfoSKAuJo) when using [jonline.io](https://jonline.io). (Note that [bullcity.social](https://bullcity.social) must permit [jonline.io](https://jonline.io) via CORS for loading to work.)

### People, Followers and Friends

Rellm allows users to create accounts and login with nothing but a username/password combo. Anyone can Follow anyone, but users can require approval for Follow Requests. Two users who Follow each other are Friends.

### Groups and Memberships

Rellm supports Groups, which are much like Usenet groups, Facebook groups, or subreddits.

### Media

Rellm [`Media`](https://rellm.org/docs/protocol#rellm-Media) is something like ActiveStorage, but with Rust and Diesel. It's straightforwardly built on content-types and blob storage. It's the reason Rellm requires S3/MinIO. Unlike [`Post`](https://rellm.org/docs/protocol#rellm-Post)s and [`Event`](https://rellm.org/docs/protocol#rellm-Event)s, [`Media`](https://rellm.org/docs/protocol#rellm-Media) is generally not shared directly. It is instead associated with [`Post`](https://rellm.org/docs/protocol#rellm-Post)s and [`Event`](https://rellm.org/docs/protocol#rellm-Event)s (for media listings) as well as Users and Groups (for their avatars).

Media is the *only* part of Rellm's APIs offered over HTTP as well as gRPC/gRPC-over-HTTP. (Hopefully the reasons for this are obvious: easy browser streaming and cache utilization for things like images.) Details on the HTTP Media APIs are in the ["Media" section](https://github.com/JonLatane/rellm/blob/main/docs/protocol.md#media) of the [protocol documentation](https://github.com/JonLatane/rellm/blob/main/docs/protocol.md).

All Media also carries [`Visibility`](https://rellm.org/docs/protocol#rellm-Visibility) and [`Moderation`](https://rellm.org/docs/protocol#rellm-Moderation) values that can be modified in the APIs, but are not currently enforced. Note that any Media visibility updates and/or deletions may take time to propagate fully, depending upon how a given Rellm instance's CDN setup works.

### AI Providers

Rellm's AI model, put concisely, is designed to let users *share* AI models providers' API keys, *without* ever actually showing/serializing keys after they're stored, and *with* token limits set by the "owner" of any API key upon their "grant" to anyone else. This means, as a server admin, you can choose to pay for your users to have AI to whatever level you want to, well, literally grant them. As a user, you can also bring your own API keys, and they're as safe as the person with *physical* access to the machine your community is running on (and, of course, you can limit/revoke keys on the provider end).

This "bring your own key (and share if you want)" setup is built atop the [`AIProvider`](https://rellm.org/docs/protocol#rellm-AIProvider) message (currently Gemini and OpenAI credentials - see [`AIProvider.provider`](https://rellm.org/docs/protocol#rellm-AIProvider) for the full oneof). Any user with the `CREATE_AI_PROVIDERS` permission can connect their own API key from their profile page, and optionally meter out access to other users on the server via [`AIProviderGrant`](https://rellm.org/docs/protocol#rellm-AIProviderGrant) - a token budget, optionally scoped to specific models.

The one feature currently built atop this is [`GenerateMedia`](https://rellm.org/docs/protocol#grpc-api-GenerateMedia) ("Generate Media…", shown next to "Edit Media…" on a Post's or Event's own page): it sends the target's own formatted content (title/description/date-time/location, reusing the same formatting [`SyncDestination`](https://rellm.org/docs/protocol#rellm-SyncDestination)s use) plus any selected reference photos to the chosen model, and attaches the result as the first item in that Post's (or Event's own Post's) media.

Which models are actually available, and what each can do ([`AIModelCapability`](https://rellm.org/docs/protocol#rellm-AIModelCapability) - generation vs. editing), is a hand-maintained catalog in [`backend/src/logic/ai_model_catalog.rs`](https://github.com/JonLatane/rellm/blob/main/backend/src/logic/ai_model_catalog.rs) - the source of truth for which models Rellm actually offers, since none of Gemini/OpenAI/Anthropic expose a stable "list models" API to build this from at request time.

#### Gemini

A Google Gemini API connection ([`GeminiCredentials`](https://rellm.org/docs/protocol#rellm-GeminiCredentials)), used for image generation/editing (e.g. generating Event posters) via Gemini's Interactions API.

#### OpenAI

An OpenAI API connection ([`OpenAICredentials`](https://rellm.org/docs/protocol#rellm-OpenAICredentials)), used for image generation/editing via OpenAI's Images API (GPT Image models).

#### Anthropic

An Anthropic API connection ([`AnthropicCredentials`](https://rellm.org/docs/protocol#rellm-AnthropicCredentials)), reserved but **not yet creatable** - Anthropic doesn't offer an image generation API, so this is defined only for forward compatibility.

#### DigitalOcean

A DigitalOcean Gradient AI Platform / Serverless Inference connection ([`DigitalOceanCredentials`](https://rellm.org/docs/protocol#rellm-DigitalOceanCredentials)), used for image *generation only* (no editing) via an OpenAI-Images-API-shaped endpoint re-hosting GPT Image and Stable Diffusion models under DigitalOcean's own billing.

### Rellm's Market

Rellm's Market ([`market.proto`](https://rellm.org/docs/protocol#market.proto)) is a small, Stripe-backed storefront a server admin can stock with up to twelve [`MarketProduct`](https://rellm.org/docs/protocol#rellm-MarketProduct)s - one of four offering types ([`PurchaseType`](https://rellm.org/docs/protocol#rellm-PurchaseType): media storage, AI token grants, Rellm hosting for a domain, or a fixed set of extra `Permission`s), each sold once (indefinitely) or on a recurring annual/monthly [`PurchasePeriod`](https://rellm.org/docs/protocol#rellm-PurchasePeriod). Buying one starts a Stripe Checkout Session; the actual [`MarketPurchase`](https://rellm.org/docs/protocol#rellm-MarketPurchase)/[`MarketSubscription`](https://rellm.org/docs/protocol#rellm-MarketSubscription) is only ever created once Stripe confirms payment via webhook, so an abandoned checkout leaves nothing behind. A recurring [`MarketSubscription`](https://rellm.org/docs/protocol#rellm-MarketSubscription) renews itself off-session against the saved payment method until either a charge fails or the buyer/admin calls [`CancelMarketSubscription`](https://rellm.org/docs/protocol#grpc-api-CancelMarketSubscription) - either way, the subscription's entitlement stays active until it's actually due to lapse, at which point the `renew_market_subscriptions` background job revokes it.

What buying each type of MarketProduct actually does:

- **Media storage** raises the buyer's `User.media_storage_limit_bytes` to the MarketProduct's configured allocation.
- **AI token grants** grant/reset an [`AIProviderGrant`](https://rellm.org/docs/protocol#rellm-AIProviderGrant) - the buyer effectively subscribes to metered access on one of the server operator's own [`AIProvider`](https://rellm.org/docs/protocol#rellm-AIProvider)s.
- **Rellm hosting** bills the buyer for the server operator to stand up a brand new Rellm instance on a domain of their choosing (e.g. "Joe's Tavern" buying `social.joestavern.com` from `rellm.org`) - this is billing only, provisioned by hand rather than automated.

Products are listed via [`GetMarketProducts`](https://rellm.org/docs/protocol#grpc-api-GetMarketProducts) (unauthenticated; admins additionally see delisted ones) and managed via [`CreateMarketProduct`](https://rellm.org/docs/protocol#grpc-api-CreateMarketProduct)/[`UpdateMarketProduct`](https://rellm.org/docs/protocol#grpc-api-UpdateMarketProduct) (Admin-only). Stripe credentials live in `ServerConfiguration.stripe_config`, Admin-only like `twilio_config`/`bird_config`.

### Posts

[`Post`](https://rellm.org/docs/protocol#rellm-Post)s follow a Twitter- or Reddit- like model. They have a [`PostContext`](https://rellm.org/docs/protocol#rellm-PostContext) as well as all-optional `title`, `link`, and `description` string values. A top-level post is stored generally the same as a reply. Posts also carry a [`Visibility`](https://rellm.org/docs/protocol#rellm-Visibility) and [`Moderation`](https://rellm.org/docs/protocol#rellm-Moderation) value that is enforced by the APIs.

Posts are also reused for Events, and will be similarly reused for future features. For developers: this is something like ActiveRecord Polymorphism, but using composition rather than inheritance at the ORM level. For users: Replies, Events, and other Rellm types track their title, description, visibility, moderation, etc. via a Post internally.

#### GroupPost

A key differentiator between [`Post`](https://rellm.org/docs/protocol#rellm-Post) and [`Media`](https://rellm.org/docs/protocol#rellm-Media) is that [`Post`](https://rellm.org/docs/protocol#rellm-Post)s and types that use them are "group-aware." That is to say: [`GroupPost`](https://rellm.org/docs/protocol#rellm-GroupPost) exists, 
linking any unique [`Group`](https://rellm.org/docs/protocol#rellm-Group) to any unique [`Post`](https://rellm.org/docs/protocol#rellm-Post), along with the [`User`](https://rellm.org/docs/protocol#rellm-User) who created that link.

### Events

[`Event`](https://rellm.org/docs/protocol#rellm-Event)s are a thin layer atop [`Post`](https://rellm.org/docs/protocol#rellm-Post)s. Any Event has a single Post, as well as at least one Occasion. An Occasion has a start time, end time, location, and RSVP/attendance data. Group Events work through the [`GroupPost`](https://rellm.org/docs/protocol#rellm-GroupPost) mechanism.

An [`Event`](https://rellm.org/docs/protocol#rellm-Event)'s ID *is* its own [`Post`](https://rellm.org/docs/protocol#rellm-Post)'s ID, and likewise an [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion)'s ID is its own Post's ID - neither carries a separate surrogate ID. [`GetEventsRequest.post_id`](https://rellm.org/docs/protocol#rellm-GetEventsRequest) looks a single Event up either way (by its own Post ID, or by any of its Occasions' Post IDs), always returning the whole Event with all its Occasions.

### Messages

[`Message`](https://rellm.org/docs/protocol#rellm-Message) is Rellm's "low trust" messaging/email system, meant to let strangers on a server make first contact (e.g. via email, with no account required) before moving to a more trusted channel. Admins have open access to all Messages on a server.

A [`MessagingGroup`](https://rellm.org/docs/protocol#rellm-MessagingGroup) is the set of participants in a Message conversation. Every [`Message`](https://rellm.org/docs/protocol#rellm-Message) belongs to one; if a client wasn't a visible recipient (e.g. they were BCC'ed), the [`Message`](https://rellm.org/docs/protocol#rellm-Message) they receive omits it.

Messages can also be delivered by email, via a [Stalwart](https://stalw.art) mail server integration (see [`deploys/email`](https://github.com/JonLatane/rellm/tree/main/deploys/email)) on the internal-only HTTP server, port 27705. Once Stalwart accepts an inbound message addressed to one of the instance's onboarded domains, it calls `POST /email` to hand it off, and Rellm turns it into a [`Message`](https://rellm.org/docs/protocol#rellm-Message): each envelope recipient's local part (before the `@`) is looked up as a username on the server, `To`/`Cc` recipients become the [`Message`](https://rellm.org/docs/protocol#rellm-Message)'s [`MessagingGroup`](https://rellm.org/docs/protocol#rellm-MessagingGroup), and `Bcc`'d recipients are recorded individually so they stay invisible to everyone else on the thread. The [`Message`](https://rellm.org/docs/protocol#rellm-Message) has no `from_user_id`, since inbound email never has a local sender; its parsed `from`/`to`/`cc` headers are stored alongside it, and the raw `.eml` is uploaded to the same MinIO store used for [`Media`](https://rellm.org/docs/protocol#rellm-Media).

### Potential future features

- Push APIs for Posts
  - Could offer more "chat" based UX
- Payments
  - Rellm should support user-to-user payments via Apple Pay, Venmo, etc.
- Products
  - Products should be flexible enough to be used for neighborhood buy/sell groups, or for independent artists or artist collectives to have a web store presence (with community/social features around it).
  - Payments should be built upon Rellm Payments.
- Transport
  - For either products or humans.
  - Fulfillment side of Rellm Products.
  - Built atop OpenStreetMap, Google Maps, or possibly let the user/server choose implmementation.
  - OSS, social-baed competitor to Uber/Lyft.

If you want these features prioritized, or have ideas about how they would fit into Rellm's design philosophy, reach out to me in any way, but especially with those payment buttons above 🙏

### Delightful Federation

A key thing that separates Rellm from Mastodon and other Fediverse projects is that its servers never talk to each other directly at all - there's no server-to-server delivery protocol. Instead, a server only *recommends* other servers by hostname (a [protocol-defined federated server](https://rellm.org/docs/protocol#federated-servers)), and it's the client - e.g. your browser, loading [jonline.io](https://jonline.io) - that calls each recommended server's API directly and merges in its posts and events, such as [bullcity.social](https://bullcity.social)'s and [oakcity.social](https://oakcity.social)'s. That's exactly why CORS is the relevant safeguard here, not server-side access control: bullcity.social and oakcity.social admins can always lock down their own CORS policy to control which other origins (i.e. other Rellm UIs) are allowed to pull their public data this way. [Cross-Protocol Federation](https://rellm.org/docs/protocol#cross-protocol-federation) is this same idea taken one step further: a Rellm client reads Mastodon and BlueSky content directly from those platforms' own public APIs and translates it into the same `Post` shape, again with no Rellm server acting as a bridge or proxy. (The one place a Rellm server *does* itself talk to another server on a user's behalf is [Sync Destinations](https://rellm.org/docs/protocol#sync-destinations) - pushing that user's own content *out* to Facebook, Mastodon, Bluesky, etc.)

Similarly, [the protocol supports federated profiles](https://github.com/JonLatane/rellm/blob/main/docs/protocol.md#federatedaccount) that allow, e.g., my profile at [jonline.io/jon](https://jonline.io/jon) to automatcally integrate information from other profiles at [bullcity.social/jon](https://bullcity.social/jon) and [oakcity.social/jon](https://oakcity.social/jon).

This approach does not seek to be particularly innovative or groundbreaking technologically. It simply aims to make it easier for people to use *existing* web standards to interact, share, plan, and play with each other, and make administrating a server simple enough that nearly anyone can do it. All you need to worry about as an administrator in this regard is a [list of servers like this](http://jonline.io/server/https:bullcity.social?tab=federation) - literally nothing but a list of hosts.

### Protocol Documentation

A benefit of being built with gRPC is that [Rellm's generated Markdown documentation is relatively easy to read and complete](https://github.com/JonLatane/rellm/blob/main/docs/protocol.md#rellm-Rellm). Rellm renders documentation as Markdown, and converts that Markdown to HTML with a separate tool. Rellm servers also always include a copy of their own protocol documentation (i.e., [https://rellm.org/docs/protocol](https://rellm.org/docs/protocol), [https://bullcity.social/docs/protocol](https://bullcity.social/docs/protocol), and [https://oakcity.social/docs/protocol](https://oakcity.social/docs/protocol)).

## Project Components

The following components are *literally* just a "nice to read" breakdown of the overall directory structure of this repository. Nonetheless, this should be a useful first pass for anyone hoping to contribute to Rellm.

### Documentation

Yes, even Rellm's documentation is documented! 😅

Rellm documentation consists of Markdown in the [`docs/` directory](https://github.com/JonLatane/rellm/tree/main/docs), starting from [`docs/README.md`](https://github.com/JonLatane/rellm/blob/main/docs/README.md).

The [Documentation root is in `docs/`](https://github.com/JonLatane/rellm/tree/main/docs). Note that `docs/protocol.md` is generated from the [gRPC APIs](#grpc-apis), and `docs/protocol.html` is generated from `docs/protocol.md` (to make the generated HTML as friendly as possible).

Additionally, the following components are *themselves* documented in `README.md` files that follow Rellm's project component structure:

- [`README.md`](https://github.com/JonLatane/rellm/blob/main/README.md#documentation-1): README Documentation Root (*literally this file you're reading right now*)
  - [`protos/README.md`](https://github.com/JonLatane/rellm/blob/main/protos/README.md): gRPC APIs
  - [`backend/README.md`](https://github.com/JonLatane/rellm/blob/main/backend/README.md): Rust Backend
  - [`frontends/README.md`](https://github.com/JonLatane/rellm/blob/main/frontends/README.md): General Frontend Information
    - [`frontends/elm/README.md`](https://github.com/JonLatane/rellm/blob/main/frontends/tamagui/README.md): Elm Frontend
    - [`frontends/tamagui/README.md`](https://github.com/JonLatane/rellm/blob/main/frontends/tamagui/README.md): Tamagui/React/Next.js Frontend
    - [`frontends/flutter/README.md`](https://github.com/JonLatane/rellm/blob/main/frontends/flutter/README.md): Flutter Frontend
  - [`deploys/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/README.md): Deployment Management
    - [`deploys/generated_certs/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/README.md): TLS Certificate Generation
  - [`.github/workflows/README.md`](https://github.com/JonLatane/rellm/blob/main/.github/workflows/README.md): CI/CD (Continuous Integration and Delivery)

### gRPC APIs

The [gRPC APIs are defined in `protos/`](https://github.com/JonLatane/rellm/tree/main/protos). In particular, [`protos/rellm.proto`](https://github.com/JonLatane/rellm/blob/main/protos/rellm.proto) is, behind this `README.md`, effectively the secondary and more technical/detailed "source of truth" for how everything in this app works. The other `.proto` files are really just "submodules" and "type definitions."

### Architecture/Deployment Management

[Rellm architecture docs live in `docs/architecture`](https://github.com/JonLatane/rellm/tree/main/docs/architecture).

At its core, Rellm is a boring client-server app; the Browser/App, HTTP server, gRPC server, PostgreSQL, and MinIO interact thusly:

![Rellm Application Architecture](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Service_Architecture.svg)

Generally, Rellm is designed to be straightforward to deploy to Kubernetes clusters so long as you have `make`, `kubectl`, and `jq`. To this end, Rellm has a "simple" deployment structure, and a more scalable alternative using Traefik:

| Simple Approach                                                                                                                                 | Scalable Approach                                                                                                                    |
| --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| ![K8s cluster with multiple Rellm Kubernetes LoadBalancers](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Kubernetes_Deployment.svg) | ![K8s with single Trafik LoadBalancer](https://github.com/JonLatane/rellm/blob/main/docs/architecture/Traefik_Kubernetes_Deployment.svg) |
|                                                                                                                                                           | See [`deploys/ingress/README.md`]([#cost-of-operation](https://github.com/JonLatane/rellm/blob/main/deploys/ingress/README.md)) for details.                                                   |

[Rellm's architecture docs](https://github.com/JonLatane/rellm/tree/main/docs/architecture) also cover and link to such topics as:

- [Deployment management, in `deploys/`](https://github.com/JonLatane/rellm/tree/main/deploys)
    - This handles Rellm as well as Postgres and MinIO.
- [TLS cert generation, in `deploys/generated_certs`](https://github.com/JonLatane/rellm/tree/main/deploys/generated_certs)
- [Traefik ingress management, in `deploys/ingress`](https://github.com/JonLatane/rellm/tree/main/deploys/ingress)

[CI/CD logic is defined in `.github/workflows/`](https://github.com/JonLatane/rellm/tree/main/.github/workflows). If you can set up a Kubernetes deployment with the instructions in [`deploys/`](https://github.com/JonLatane/rellm/tree/main/deploys), it should be straightforward to integrate your own CI into 

### Rust Backend

The [Rust backend, in `backend/`](https://github.com/JonLatane/rellm/tree/main/backend), is built with [Diesel](https://diesel.rs) and [Tonic](https://github.com/hyperium/tonic).

### Frontends

[Rellm Frontends are grouped together in `frontends/`.](https://github.com/JonLatane/rellm/tree/main/frontends) Specific iOS, Android, and/or desktop frontends would be welcome contributions!

#### Elm Frontend

The [Elm frontend, in `frontends/elm-spa`](https://github.com/JonLatane/rellm/tree/main/frontends/elm-spa), is the new "public Web face" of any Rellm instance. It's built with [Elm](https://elm-lang.org/) and [Elm-Spa](https://www.elm-spa.dev).

#### Tamagui/React/Next.js Frontend

The [Tamagui frontend, in `frontends/tamagui`](https://github.com/JonLatane/rellm/tree/main/frontends/tamagui), was, until recently, the "public Web face" of any Rellm instance. It's the most "complete" UI, and some features can still only be edited in this UI. It's built with [Tamagui](https://tamagui.dev) (a somewhat Flutter-like UI toolkit and build system built atop [yarn](https://yarnpkg.com/), [React](https://react.dev), [React Native](https://reactnative.dev), and [Next.JS](https://nextjs.org)), along with [Redux](https://redux.js.org) among others.

Notably, in the future, with Tamagui, it should be possible to build iOS/Android apps from the existing Rellm source (after some effort to port less-native-friendly third-party components).

#### Flutter Frontend (Deprecated/Frozen for Reference)

The Flutter frontend is deprecated, unless someone would like to maintain it. It's just not feasible to maintain a Flutter app long-term, IMO. I love the UI framework but its ecosystem changes rapidly underneath you as a developer. It's removed from CI/CD, including the server. At some point it will be deleted from the repo entirely.

The [Flutter frontend, in `frontends/flutter`](https://github.com/JonLatane/rellm/tree/main/frontends/flutter), is built with vanilla Flutter, [Provider](https://pub.dev/packages/provider), [`auto_route`](https://pub.dev/packages/auto_route), and [`protoc_plugin`](https://pub.dev/packages/protoc_plugin), among others.

## Quick deploy to your own cluster

This section is the fastest path to a running cluster; see [`deploys/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/README.md) for the full reference on everything else `make`/`rellm deploy` can do here - multi-namespace setups, pointing domains at your deployment, TLS certs, Postgres upgrades, and more. (Already on Homebrew or the Linux package? See [Deploying to Kubernetes from Homebrew/Linux](#deploying-to-kubernetes-from-homebrewlinux-rellm-deploy) - you can skip straight to `rellm deploy` without cloning this repo.)

If you have `kubectl` and `make`, you can be setup in a few minutes. (If you're looking for a quick, fairly priced, scalable Kubernetes host, [I recommend DigitalOcean](https://m.do.co/c/1eaa3f9e536c).) First make sure `kubectl` is setup correctly and your instance has the `rellm` namespace available with `kubectl get services` and `kubectl get namespace rellm`:

```bash
$ kubectl get services
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.245.0.1   <none>        443/TCP   161d
# You should not be using a Kubernetes namespace named rellm; otherwise, existing services could be overridden.
$ kubectl get namespace rellm
Error from server (NotFound): namespaces "rellm" not found
```

To begin setup, first clone this repo:

```bash
git clone https://github.com/JonLatane/rellm.git
cd rellm
```

(On Homebrew or the Linux package instead? Skip the clone - see [Deploying to Kubernetes from Homebrew/Linux](#deploying-to-kubernetes-from-homebrewlinux-rellm-deploy).)

Next, from the repo root, to create Postgres, Minio and two load-balanced Rellm servers in the namespace `rellm` (plus a few recurring jobs), run:

```bash
# THIS STEP WILL COST MONEY WITH MOST KUBERNETES PROVIDERS. ($12/mo. at DigitalOcean)
# The create_external_backend Make target, specifically, will create the Joline service as a K8s LoadBalancer.
# Of course, it costs nothing to use Minikube.
# To deploy for use with a different ingress (say, a shared nginx, or Rellm's pending internal LB), use create_internal_backend or deploy_be_internal_insecure_create to deploy it as a K8s ClusterIP instead.
# NAMESPACE is required (no default) - pick whichever namespace you want this deployed to.
NAMESPACE=rellm make create_backend_data create_external_backend
```

That's it! You've created Minio and Postgres servers along with an *unsecured Rellm instance* where ***passwords and auth tokens will be sent in plain text*** (You should secure it immediately if you care about any data/people, but feel free to play around with it until you do! Simply `NAMESPACE=rellm make delete_backend_data create_backend_data restart_backend` to reset your server's data.) Because Rellm is a very tiny Rust service, it will all be up within seconds. Your Kubenetes provider will probably take some time to assign you an IP, though.

Simply `kubectl delete namespace rellm` to delete your deployment (or see below for more detailed management instructions).

### Deployment management: domains and TLS certs; deploying multiple `rellm` instances to different K8s namespaces in the same cluster; and cross-namespace load balancing with Traefik

[`deploys/Makefile`](https://github.com/JonLatane/rellm/blob/main/deploys/Makefile), [`deploys/generated_certs/Makefile`](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/Makefile), and a few of Rellm's Rust binaries (mostly the main `rellm` server) provide the tools to update your deployment, point a domain at it, manage TLS certificates, and more.

For details on these scenarios and more when deploying to your own cluster, see [`deploys/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/README.md), [`deploys/generated_certs/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/generated_certs/README.md), and [`deploys/ingress/README.md`](https://github.com/JonLatane/rellm/blob/main/deploys/ingress/README.md).

## Motivations

Signal is really good for private communication and group chats. However, we need something like this for public community organizing, and really alternative social media in general. In my opinion, ActivityPub and ATProto are at the same time limited in terms of actual social management features, outright bad at events management, and they're badly documented and unclear APIs. Rellm seeks to be a very pragmatic Reddit/Twitter/Usenet/Facebook Events hybrid that doesn't do algorithmic rankings at all.

Most of all, though, I'd just really be happy if using Rellm for your community brought you some joy.
