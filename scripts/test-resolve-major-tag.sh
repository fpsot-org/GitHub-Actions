#!/usr/bin/env bash
# Tests for resolve-major-tag.sh against a local repository with known tags.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
git init -q "$work/src"
git -C "$work/src" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
for t in v0.1.0 v0.2.0 v0.10.0 v0.3.0-rc.1 v1.0.0 v10 latest; do
  git -C "$work/src" -c tag.gpgsign=false tag "$t"
done
git clone -q --bare "$work/src" "$work/repo.git"
url="file://$work/repo.git"
check() { # major expected-output expected-rc
  out="$(bash "$here/resolve-major-tag.sh" "$url" "$1" 2>&1)"; rc=$?
  if [ "$rc" -ne "$3" ] || [ "$out" != "$2" ]; then
    echo "FAIL: major $1: got rc=$rc out='$out', want rc=$3 out='$2'"; fail=1
  fi
}
check 0 v0.10.0 0
check 1 v1.0.0 0
check 2 "no v2.Y.Z tag in $url" 3
[ $fail -eq 0 ] && echo "PASS"
exit $fail
