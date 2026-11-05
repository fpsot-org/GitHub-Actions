#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Golden tests for ProseLint.java. Files ending in -fr.adoc run with --lang fr;
# files ending in -us.adoc run with --us-spelling.
set -u
cd "$(dirname "$0")"
fail=0
for f in testdata/*.adoc; do
  name="${f%.adoc}"
  lang=en
  case "$name" in *-fr) lang=fr ;; esac
  extra=()
  case "$name" in *-us) extra=(--us-spelling) ;; esac
  actual="$(java ProseLint.java --lang "$lang" "${extra[@]}" "$f" 2>&1)"
  if ! diff -u "$name.expected" <(printf '%s\n' "$actual") >/dev/null; then
    echo "FAIL: $f"
    diff -u "$name.expected" <(printf '%s\n' "$actual")
    fail=1
  fi
done
[ $fail -eq 0 ] && echo "PASS"
exit $fail
