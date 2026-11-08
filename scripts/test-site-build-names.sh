#!/usr/bin/env bash
# Tests that site-build.sh map refuses a repo name that is not fpsot-spec-<name>,
# or whose <name> is reserved, before it touches the site folder. Its cleanup
# would otherwise delete home content, such as content/fr or public/.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
mkdir -p "$work/site/content/fr" "$work/site/content/_src" "$work/site/public"
touch "$work/site/content/fr/keep" "$work/site/content/_src/keep" "$work/site/public/keep" "$work/site/content/keep"
for bad in fpsot-spec- fpsot-spec-fr fpsot-spec-_src other-repo fpsot-spec-../x fpsot-spec-Bad 'fpsot-spec-a b'; do
  if SPEC_SOURCE_DIR="$work/none" bash "$here/site-build.sh" map "$work/site" "$bad" v0.1.0 "$work/out" >"$work/log" 2>&1; then
    echo "FAIL: map accepted repo name '$bad'"; fail=1
  elif ! grep -q 'not a valid spec repo name' "$work/log"; then
    echo "FAIL: map refused '$bad' for another reason:"; cat "$work/log"; fail=1
  fi
  for f in content/fr/keep content/_src/keep public/keep content/keep; do
    [ -e "$work/site/$f" ] || { echo "FAIL: map with '$bad' deleted $f"; fail=1; touch "$work/site/$f"; }
  done
done
[ "$fail" = 0 ] && echo PASS
exit "$fail"
