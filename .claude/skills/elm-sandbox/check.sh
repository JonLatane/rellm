#!/usr/bin/env bash
# Compile, lint and test the Elm SPA in the Claude cloud sandbox. See SKILL.md.
#
#   check.sh            compile + elm-review + tests
#   check.sh compile    just the compile (fastest real compiler errors)
#   check.sh review     just elm-review
#   check.sh test       just the tests (elm-test-rs --offline)
#   check.sh build      production build into frontends/elm-spa/public/dist (what serve.cjs serves)
#
# The sandbox only has Elm 0.19.1, but elm.json (and review/elm.json) say 0.19.3, which makes every
# Elm tool refuse to run. This script rewrites the version for the duration of the run and ALWAYS
# restores the files afterwards (trap), so nothing version-patched can end up in a commit.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT/frontends/elm-spa"
export PATH="$PWD/node_modules/.bin:$PATH"

[ -d node_modules ] || npm ci --silent

FILES=(elm.json review/elm.json)
for f in "${FILES[@]}"; do cp "$f" "$f.sandbox-bak"; done
restore() { for f in "${FILES[@]}"; do [ -f "$f.sandbox-bak" ] && mv -f "$f.sandbox-bak" "$f"; done; }
trap restore EXIT
sed -i 's/"elm-version": "0.19.3"/"elm-version": "0.19.1"/' "${FILES[@]}"

what="${1:-all}"
status=0

# Only the Elm compiler's *errors* matter; its progress output is carriage-return spam.
quiet() { tr '\r' '\n' | grep -v -E '^(Compiling|Verifying)' ; }

if [ "$what" = all ] || [ "$what" = compile ]; then
  echo "== compile"
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
