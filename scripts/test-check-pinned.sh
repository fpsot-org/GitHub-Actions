#!/usr/bin/env bash
# Tests for check-pinned.sh.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
if ! bash "$here/check-pinned.sh" "$here/testdata/pinned/ok.yml" >/dev/null; then
  echo "FAIL: ok.yml should pass"; fail=1
fi
out="$(bash "$here/check-pinned.sh" "$here/testdata/pinned/unpinned.yml")"; rc=$?
if [ $rc -ne 1 ]; then echo "FAIL: unpinned.yml should exit 1, got $rc"; fail=1; fi
case "$out" in
  *"unpinned action actions/checkout@v4"*) ;;
  *) echo "FAIL: missing message, got: $out"; fail=1 ;;
esac
# The same image pinned by two digests in two workflows: one of them is stale.
out="$(bash "$here/check-pinned.sh" "$here/testdata/pinned/digests")"; rc=$?
if [ $rc -ne 1 ]; then echo "FAIL: digests/ should exit 1, got $rc"; fail=1; fi
case "$out" in
  *"ghcr.io/example/builder is pinned to more than one digest"*) ;;
  *) echo "FAIL: missing digest message, got: $out"; fail=1 ;;
esac
if ! bash "$here/check-pinned.sh" "$here/testdata/pinned/digests/build.yml" >/dev/null; then
  echo "FAIL: one digest should pass"; fail=1
fi
[ $fail -eq 0 ] && echo "PASS"
exit $fail
