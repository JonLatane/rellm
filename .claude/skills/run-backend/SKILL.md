---
name: run-backend
description: Run or rebuild the local Rellm Rust backend, with or without a frontend baked in. Use when the user wants to start/restart the backend server, test backend changes, or check a Tamagui/Elm change as served by the Rust server itself.
---

Rellm's backend is a Rust (cargo) server, driven entirely through `backend/Makefile`.

## Starting the backend

```
cd backend && make local_object_storage_start run
```

- `local_object_storage_start` starts the `rellm-dev-object-storage` Docker container (creates it via `local_object_storage_create` if it doesn't exist yet).
- `run` is just `cargo run`.
- The server listens on **ports 80 and 8000** locally.
- The user often has this running themselves already. It is safe to kill their dev server and restart it — the user has said this explicitly. To stop it: `cd backend && make local_instances_stop` (runs `killall rellm`), or find/kill whatever process is bound to ports 80/8000.

## Rebuilding a frontend and serving it through the Rust server

These are the right targets when you want to validate a Tamagui or Elm change *as served by the backend* (as opposed to that frontend's own standalone dev server):

```
cd backend && make rebuild_tamagui_and_run   # rebuilds Tamagui FE, then cargo run
cd backend && make rebuild_elm_and_run       # rebuilds Elm FE, then cargo run
```

Prefer `rebuild_tamagui_and_run` over Tamagui's own dev server when sanity-checking a change — Tamagui's own dev loop (see the `run-tamagui` skill) is much slower to build/iterate with.

## Other useful backend targets

- `make build` / `make clean` — plain cargo build/clean.
- `make rebuild_protos` — `cargo clean -p prost-build` then `build`, to force proto regeneration on the Rust side (see the `rebuild-protos` skill for the full multi-frontend proto rebuild).
- `make local_db_create` / `local_db_drop` / `local_db_reset` / `local_db_connect` — manage the local `rellm_dev` Postgres database.
- `make local_object_storage_delete` — stop and remove the object storage container entirely.
- `make test_authentication_local` — resets the local DB, boots the server, and runs a grpcurl-based auth smoke test (create account / login, including expected-failure cases) against `localhost:27707`, then stops the server again.
