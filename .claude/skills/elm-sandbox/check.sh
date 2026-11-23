#!/usr/bin/env bash
# Compile, lint and test the Elm SPA in the Claude cloud sandbox. See SKILL.md.
#
#   check.sh            compile + elm-review + tests
#   check.sh compile    just the compile (fastest real compiler errors)
#   check.sh review     just elm-review
#   check.sh test       just the tests (elm-test-rs --offline)
#   check.sh build      production build into frontends/elm-spa/public/dist (what serve.cjs serves)
#
# Uses the Elm the project pins (package.json, installed into node_modules by `npm ci`), NOT the
# older global `elm` on PATH. Nothing is patched: elm.json/review/elm.json are never modified.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT/frontends/elm-spa"

want="$(sed -n 's/.*"elm": *"\([0-9.]*\)\(-[0-9]*\)\?".*/\1/p' package.json | head -1)"
have="$(node_modules/.bin/elm --version 2>/dev/null || true)"
if [ -z "$have" ] || [ "$have" != "$want" ]; then
  echo "node_modules has Elm '${have:-none}', project pins $want -- running npm ci"
  rm -rf node_modules && npm ci --silent || { echo "npm ci failed"; exit 1; }
  have="$(node_modules/.bin/elm --version 2>/dev/null || true)"
fi
if [ "$have" != "$want" ]; then
  echo "Elm in node_modules is '$have', expected $want -- not checking with the wrong compiler"
  exit 1
fi
# `npm ci` can rewrite yarn.lock's platform-specific @elm_binaries entry; never commit that.
git checkout -q -- yarn.lock 2>/dev/null || true

# elm-spa and elm-review shell out to `elm`: make sure they find the pinned one, not the global.
export PATH="$PWD/node_modules/.bin:$PATH"

what="${1:-all}"
status=0

# Only the compiler's *errors* matter; its progress output is carriage-return spam.
quiet() { tr '\r' '\n' | grep -v -E '^(Compiling|Verifying)' ; }

if [ "$what" = all ] || [ "$what" = compile ]; then
  echo "== compile (Elm $have)"
  elm-spa gen >/dev/null 2>&1   # Gen.*/Route/Request only exist once generated
  elm make src/Main.elm --output=/tmp/elm-sandbox-out.js 2>&1 | quiet; [ "${PIPESTATUS[0]}" = 0 ] || status=1
fi
if [ "$what" = all ] || [ "$what" = review ]; then
  echo "== elm-review"
  elm-spa gen >/dev/null 2>&1
  elm-review --no-color 2>&1 | quiet; [ "${PIPESTATUS[0]}" = 0 ] || status=1
fi
if [ "$what" = all ] || [ "$what" = test ]; then
  echo "== tests"
  elm-test-rs --offline 2>&1 | quiet | tail -25; [ "${PIPESTATUS[0]}" = 0 ] || status=1
fi
if [ "$what" = build ]; then
  echo "== build"
  elm-spa build 2>&1 | quiet; [ "${PIPESTATUS[0]}" = 0 ] || status=1
fi

[ "$status" = 0 ] && echo "ALL OK" || echo "FAILURES (see above)"
exit "$status"
