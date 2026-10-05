#!/bin/bash
#
# Runs every deploys/tests/*_tests.sh (or just the ones named, e.g. `tests/run.sh guard flags`) and
# fails if any does. No cluster needed -- see lib.sh. `make -C deploys test` runs this.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if [ $# -gt 0 ]; then
  files=()
  for name in "$@"; do
    files+=("${name%_tests.sh}_tests.sh")
  done
else
  files=(*_tests.sh)
fi

failed=()
for file in "${files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "No such test file: $file" >&2
    exit 2
  fi
  bash "$file" || failed+=("$file")
done

echo
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "All deploys tests passed (${#files[@]} files)."
