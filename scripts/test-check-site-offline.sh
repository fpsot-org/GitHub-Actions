#!/usr/bin/env bash
# Tests check-site-offline.sh: a site without external requests passes; a CDN
# stylesheet, an external script and a CSS import from another host fail.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
data="$here/../testdata/site-offline"
fail=0
out=$(bash "$here/check-site-offline.sh" "$data/good" 2>&1) || { echo "FAIL: good site rejected: $out"; fail=1; }
for bad in bad-cdn bad-script bad-css bad-style-tag bad-style-attr bad-svg-image bad-base bad-refresh bad-onclick bad-inline-script; do
  if out=$(bash "$here/check-site-offline.sh" "$data/$bad" 2>&1); then
    echo "FAIL: $bad accepted"; fail=1
  elif ! grep -q "$bad/" <<<"$out"; then
    echo "FAIL: $bad: the message does not name the file: $out"; fail=1
  fi
done
[ $fail -eq 0 ] && echo "PASS"
exit $fail
