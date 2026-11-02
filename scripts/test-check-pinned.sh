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
[ $fail -eq 0 ] && echo "PASS"
exit $fail
