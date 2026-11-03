#!/usr/bin/env bash
# Tests for fetch-spec-file.sh against a local repository.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
g() { git -C "$work/src" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
git init -q "$work/src"
mkdir -p "$work/src/model"
echo one > "$work/src/model/m.yaml"; g add .; g commit -q -m one; g tag v0.1.0
first=$(g rev-parse HEAD)
echo two > "$work/src/model/m.yaml"; g commit -q -am two; g tag v0.2.0
echo three > "$work/src/model/m.yaml"; g commit -q -am three
git clone -q --bare "$work/src" "$work/repo.git"
url="file://$work/repo.git"
check() { # ref expected-content
  rm -f "$work/out"
  if ! out=$(bash "$here/fetch-spec-file.sh" "$url" "$1" model/m.yaml "$work/out" 2>&1); then
    echo "FAIL: ref '$1': $out"; fail=1; return
  fi
  [ "$(cat "$work/out")" = "$2" ] || { echo "FAIL: ref '$1': got '$(cat "$work/out")', want '$2'"; fail=1; }
}
check "" two          # highest v0 tag
check v0.1.0 one      # explicit tag
check "$first" one    # commit SHA
if bash "$here/fetch-spec-file.sh" "$url" "" missing.yaml "$work/out" >/dev/null 2>&1; then
  echo "FAIL: a missing file should fail"; fail=1
fi
[ $fail -eq 0 ] && echo "PASS"
exit $fail
