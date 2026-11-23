#!/usr/bin/env bash
# One-time (per container) setup so Elm 0.19.x tooling works in the Claude cloud sandbox.
# See SKILL.md. Idempotent: safe to re-run; skips packages already in ~/.elm.
#
# The sandbox proxy blocks Elm's package site (package.elm-lang.org, and github.com/*/zipball/*), but
# plain `git clone` of public GitHub repos works. Elm's package cache is just
# ~/.elm/0.19.1/packages/<author>/<name>/<version>/ holding the package's source, so we `git clone`
# each dependency at its version tag straight into it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ELM_SPA="$ROOT/frontends/elm-spa"

python3 - "$ELM_SPA" <<'PY'
import json, os, re, shutil, subprocess, sys

elm_spa = sys.argv[1]
failed = []

# Each Elm release keeps its own package cache: ~/.elm/<elm version>/packages. The npm-pinned compiler
# (package.json "elm") is what check.sh uses, so that is the one that must be filled; 0.19.1 is also
# filled for anyone using the older global `elm`. Everything is cloned into `base` and copied to the rest.
pinned = re.search(r'"elm":\s*"(\d+\.\d+\.\d+)', open(f"{elm_spa}/package.json").read()).group(1)
cache_dirs = [os.path.expanduser(f"~/.elm/{v}/packages") for v in dict.fromkeys([pinned, "0.19.1"])]
base = cache_dirs[0]
for d in cache_dirs:
    os.makedirs(d, exist_ok=True)


def sync(pkg, ver):
    """Copy `pkg ver` from `base` into the other versions' caches."""
    src = f"{base}/{pkg}/{ver}"
    for d in cache_dirs[1:]:
        dst = f"{d}/{pkg}/{ver}"
        if not os.path.isdir(dst + "/src") and os.path.isdir(src):
            shutil.rmtree(dst, ignore_errors=True)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copytree(src, dst)


def get(pkg, ver):
    d = f"{base}/{pkg}/{ver}"
    if os.path.isdir(d + "/src"):
        sync(pkg, ver)
        return d
    tmp = d + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    r = subprocess.run(
        ["git", "clone", "-q", "--depth", "1", "--branch", ver, f"https://github.com/{pkg}", tmp],
        capture_output=True, text=True, timeout=180,
    )
    if r.returncode:
        print(f"FAILED {pkg} {ver}: {r.stderr[-200:]}", file=sys.stderr)
        failed.append(f"{pkg} {ver}")
        return None
    shutil.rmtree(tmp + "/.git", ignore_errors=True)
    shutil.rmtree(d, ignore_errors=True)
    os.rename(tmp, d)
    sync(pkg, ver)
    print(f"cloned {pkg} {ver}")
    return d


def app_deps(path):
    j = json.load(open(path))
    deps = {}
    for section in ("dependencies", "test-dependencies"):
        for kind in ("direct", "indirect"):
            deps.update(j.get(section, {}).get(kind, {}))
    return deps


seen = set()


def walk_package(pkg, ver):
    """A *package* (not an application) declares ranges, so pick an installed version in range."""
    if (pkg, ver) in seen:
        return
    seen.add((pkg, ver))
    d = get(pkg, ver)
    if not d:
        return
    for p, constraint in json.load(open(d + "/elm.json")).get("dependencies", {}).items():
        m = re.match(r"(\d+\.\d+\.\d+) <= v < (\d+)", constraint)
        if not m:
            continue
        lo = m.group(1)
        have = os.listdir(f"{base}/{p}") if os.path.isdir(f"{base}/{p}") else []
        cands = [v for v in have if v.split(".")[0] == lo.split(".")[0] and os.path.isdir(f"{base}/{p}/{v}/src")]
        walk_package(p, sorted(cands)[-1] if cands else lo)


for project in (f"{elm_spa}/elm.json", f"{elm_spa}/review/elm.json"):
    for pkg, ver in app_deps(project).items():
        get(pkg, ver)

# elm-test-rs's own runner package (version must match what the installed elm-test-rs asks for; it
# says so in its "no version of mpizenberg/elm-test-runner in X" error if this ever changes).
walk_package("mpizenberg/elm-test-runner", "6.0.1")

if failed:
    print(f"\nSetup INCOMPLETE -- {len(failed)} package(s) could not be cloned (re-run to retry):", file=sys.stderr)
    for f in failed:
        print(f"  {f}", file=sys.stderr)
    sys.exit(1)
PY

echo "Done. Next: .claude/skills/elm-sandbox/check.sh (installs the project's pinned Elm with npm ci if needed)"
