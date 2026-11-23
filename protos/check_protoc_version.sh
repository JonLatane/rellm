#!/usr/bin/env bash
# Fails unless `protoc` on PATH is exactly the version in protos/PROTOC_VERSION -- the version CI's
# "Test Proto/Docs Consistency" job installs and regenerates with. Generated bindings are committed
# (Flutter, Tamagui, Elm), and protoc's own bundled .proto files (google/protobuf/timestamp.proto,
# field_mask.proto, ...) are embedded in them with comments that change between releases, so
# generating with any other version makes that CI job fail on files you never touched.
#
# Run by every target that invokes protoc (`make protos`, the per-frontend protos targets,
# `yarn protos`). To upgrade protoc on purpose: install it, put the new version in
# protos/PROTOC_VERSION (CI installs whatever that file says), run `make protos`, commit it all.
# ALLOW_PROTOC_MISMATCH=1 skips the check (for experiments; don't commit the output).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED="$(tr -d '[:space:]' < "$HERE/PROTOC_VERSION")"
ACTUAL="$(protoc --version 2>/dev/null | awk '{print $NF}' || true)"

[ "$ACTUAL" = "$EXPECTED" ] && exit 0
[ -n "${ALLOW_PROTOC_MISMATCH:-}" ] && { echo "WARNING: protoc is ${ACTUAL:-missing}, expected $EXPECTED (ALLOW_PROTOC_MISMATCH set) -- don't commit the generated output." >&2; exit 0; }

cat >&2 <<MSG
ERROR: protoc ${ACTUAL:-not found} is on PATH, but this repo generates bindings with protoc $EXPECTED (protos/PROTOC_VERSION).
  Generating with another version churns committed files (protoc's bundled google/protobuf/*.proto comments change
  between releases) and fails CI's "Test Proto/Docs Consistency" job.

  * Install protoc $EXPECTED: https://github.com/protocolbuffers/protobuf/releases/tag/v$EXPECTED
    (macOS: download protoc-$EXPECTED-osx-aarch_64.zip, or \`brew install protobuf\` if Homebrew's is $EXPECTED).
  * Upgrading protoc on purpose? Put the new version in protos/PROTOC_VERSION, re-run \`make protos\`, and
    commit the result together with that file -- CI installs whatever it says.
  * Just experimenting: ALLOW_PROTOC_MISMATCH=1 make protos (don't commit the output).
MSG
exit 1
