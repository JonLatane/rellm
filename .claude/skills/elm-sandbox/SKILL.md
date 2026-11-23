---
name: elm-sandbox
description: Compile, lint, test, and drive the Elm SPA (frontends/elm-spa) inside the Claude cloud/remote sandbox, where Elm's package site is blocked and the global `elm` on PATH is an older 0.19.1. Use whenever you are in a Claude Code cloud session and need real compiler errors, elm-review, elm-test, or a headless-browser check of an Elm change -- before pushing, instead of relying on CI to find type errors.
---

In the Claude cloud sandbox the normal Elm commands (`make build`, `make test`, `npx elm-test-rs`, `elm make`) fail, for two unrelated reasons:

1. **Elm's package site is blocked.** `package.elm-lang.org` and `github.com/*/zipball/*` (what `elm` downloads packages from) are refused by the sandbox proxy (`400 Bad Request` / `403`), and `elm-test-rs` can't fetch the package index. But plain `git clone` of public GitHub repos works, and Elm's package cache is just each package's source at its version tag, in `~/.elm/<elm version>/packages/<author>/<name>/<version>/`.
2. **The `elm` on PATH is the wrong one.** `/opt/node22/bin/elm` is an older 0.19.1; the project pins **0.19.3** (`package.json`), installed into `frontends/elm-spa/node_modules` by `npm ci` (npm itself is reachable). A bare `elm`/`elm-spa` then aborts with `ELM VERSION MISMATCH`. Always use the pinned one -- `check.sh` does. **Do not** rewrite `"elm-version"` in `elm.json` to make the old compiler run, and don't `npm i elm@<other>` into `node_modules`: that silently makes every later check use the wrong compiler.

Skipping this and "checking by reading the code" is how type errors reach CI -- a type annotation left on an old type (`Dict String (List Post)` after the value became a record) failed CI twice before this skill existed. **Run `check.sh` before pushing any Elm change.**

## Quick start

```
cd /path/to/rellm
.claude/skills/elm-sandbox/setup.sh     # once per container (~20s): git-clones the packages into ~/.elm
.claude/skills/elm-sandbox/check.sh     # compile + elm-review + tests (~1 min). Prints ALL OK or what failed.
```

`check.sh compile|review|test|build` runs just one step. It runs `npm ci` itself if `node_modules` is missing or holds a different Elm than `package.json` pins (and refuses to check with the wrong compiler). Nothing in the repo is patched. Two side effects to know about: `npm ci` can rewrite `frontends/elm-spa/yarn.lock`'s platform-specific `@elm_binaries` entry (when `check.sh` has to run `npm ci` it puts `yarn.lock` back exactly as it was beforehand, so your own lockfile edits are kept; check `git status` before committing anyway), and `elm-spa gen` writes the (gitignored) generated routing code.

`setup.sh` is idempotent (skips what's cached) and exits nonzero if any package couldn't be cloned (re-run to retry). It reads both `elm.json` files plus the test runner package `elm-test-rs` needs (`mpizenberg/elm-test-runner`; if `elm-test-rs --offline` ever says "no version of X in Y", bump the version in `setup.sh`), and fills the cache for the pinned Elm *and* 0.19.1 -- each Elm release has its own cache directory, so a cache filled for one is invisible to the other. The caches live in the container, so a fresh session needs `setup.sh` again.

What each step is:

- **compile** runs `elm-spa gen` first (`Gen.*`, `Route`, `Request` only exist once generated -- a bare `elm make` shows spurious missing-module errors) and then `elm make src/Main.elm`. This is the real compiler, so it catches type errors in code paths nothing exercises.
- **elm-review** is what CI gates on (`NoUnused.*`, `NoPrematureLetComputation`, ...). It is *not* part of `elm make`: an unused function, or a `let` value computed before an `if` that doesn't always use it, passes the compiler and fails CI.
- **tests** is `elm-test-rs --offline` (967 tests at time of writing). `--offline` makes it use the cache instead of the blocked package index; plain `elm-test` isn't needed.

## Driving the app in a headless browser

Chromium and Playwright are pre-installed (`require('playwright')` works from any CommonJS script, no `npm install`; ESM `import` does not find it). The `run-elm` skill's `driver.mjs` needs `elm-spa server`, which won't start under 0.19.3 -- instead build once and serve the static output:

```
.claude/skills/elm-sandbox/check.sh build                 # -> frontends/elm-spa/public/dist/elm.js (gitignored)
node .claude/skills/elm-sandbox/serve.cjs 1234 &           # static server (loopback only) + SPA fallback; optional 2nd arg = another public/ dir
node .claude/skills/elm-sandbox/ui-check-starred.cjs       # worked example, see below
```

Rebuild (`check.sh build`, ~1 min) after each Elm change; the server serves whatever is in `public/` live. CSS under `public/style/` is served directly, no rebuild.

There is no Rellm backend in the sandbox (needs Postgres + MinIO), and no Bluesky/Mastodon accounts, so **stub the network**. `ui-check-starred.cjs` is a worked example for the Starred panel:

- `context.route(url => host isn't localhost, handler)` intercepts every outbound request; answer with fake Bluesky XRPC JSON (`getActorLikes`, `getPosts`, `getPostThread`, `createRecord`, `deleteRecord`) and a 404 for anything else. Answer `OPTIONS` preflights with `access-control-allow-origin: *`.
- Seed a connected account before the page loads with `ctx.addInitScript(() => localStorage.setItem(...))`. Persisted state keys (all in `public/index.html`): `rellmBlueskyAccounts` (array of `{handle, accessToken, refreshToken, enabled, avatarUrl, displayName, sortOrder, needsReauth, pdsHost}`), `rellmMastodonAccountsAndServers`, `rellmStarredPosts`, `rellmState`, `rellmUserPreferences`.
- Make the stub reproduce the *condition*, not just the happy path: e.g. the fake AppView only reports a new like after `indexLagMs`, which is what exposes the "starred post vanishes from the Server tab" bug.
- Read state from the DOM and print a time series (`badge over time: 0ms:1 ... 1000ms:1↻ ...`) rather than relying on one screenshot -- a 0.25s transition or a ~1s spinner is easy to miss. Screenshots: `page.screenshot({ clip })` to zoom; `deviceScaleFactor: 2` if a person will look. View the PNG with `Read`; one you didn't look at proves nothing.
- Starred button gotchas: the bottom-right badge counts server stars *not also starred in this browser*, so starring a post doesn't change it -- check the panel's Server tab count instead. A badge's `textContent` includes the (visually hidden) `↻` glyph; strip it. The closed panel still contains `.post-star` elements, so click `.post-star >> visible=true`.

### Prove a UI check can fail (control run)

A check that has only ever passed proves little. Build the pre-change commit and run the same script against it:

```
git worktree add --detach /tmp/wt <old-commit>
cd /tmp/wt/frontends/elm-spa && ln -s /path/to/rellm/frontends/elm-spa/node_modules node_modules   # reuse the pinned Elm
PATH=$PWD/node_modules/.bin:$PATH npx elm-spa build
node /path/to/rellm/.claude/skills/elm-sandbox/serve.cjs 1235 /tmp/wt/frontends/elm-spa/public &
APP=http://localhost:1235 node /path/to/rellm/.claude/skills/elm-sandbox/ui-check-starred.cjs   # should FAIL on the old code
git worktree remove --force /tmp/wt
```

For the Starred panel fix this showed the old code ending with the Server tab at 1 (the new like lost) and the fixed code at 2.

## What this can't cover

Real Bluesky/Mastodon/Rellm servers (credentials), and the PWA/service-worker and push-notification paths. Say so when reporting a result rather than implying a live check happened.
