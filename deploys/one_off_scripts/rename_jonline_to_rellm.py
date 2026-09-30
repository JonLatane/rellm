#!/usr/bin/env python3
"""Case-preserving 'jonline' -> 'rellm' substitution over a list of files
(read one path per line from stdin, as produced by `git ls-files`).

Protects the literal jonline.io / Jonline.io / JONLINE.IO domain -- the one
mention of the old name that's a live hostname, not the project name, and
must not change.
"""
import os
import sys

REPLACEMENTS = [
    ("JONLINE", "RELLM"),
    ("Jonline", "Rellm"),
    ("jonline", "rellm"),
]

DOMAIN_GUARDS = [
    ("JONLINE.IO", "\0RELLM_RENAME_GUARD_UPPER\0"),
    ("Jonline.io", "\0RELLM_RENAME_GUARD_TITLE\0"),
    ("jonline.io", "\0RELLM_RENAME_GUARD_LOWER\0"),
]


def rewrite(text: str) -> str:
    for literal, guard in DOMAIN_GUARDS:
        text = text.replace(literal, guard)
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    for literal, guard in DOMAIN_GUARDS:
        text = text.replace(guard, literal)
    return text


def main():
    changed = 0
    for line in sys.stdin:
        path = line.rstrip("\n")
        if not path or os.path.islink(path) or not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
            original = f.read()
        updated = rewrite(original)
        if updated != original:
            with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
                f.write(updated)
            changed += 1
    print(f"rewrote {changed} files", file=sys.stderr)


if __name__ == "__main__":
    main()
