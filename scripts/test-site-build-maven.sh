#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Tests that the Roq build of site-build.sh asks Maven for no "clean" goal, so the
# build needs no plugin the website builder image does not hold (Maven Central
# refuses parallel CI downloads with 429), and that it still removes the output
# of an earlier build. Uses a fake Maven: needs only bash.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
mkdir -p "$work/site/target/roq" "$work/bin"
echo stale > "$work/site/target/roq/stale.html"
cat > "$work/bin/mvn" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$FAKE_MVN_ARGS"
mkdir -p target/roq && echo new > target/roq/index.html
EOF
chmod +x "$work/bin/mvn"
FAKE_MVN_ARGS="$work/args" MVN="$work/bin/mvn" bash "$here/site-build.sh" home "$work/site" "$work/out" \
  || { echo "FAIL: home build failed"; fail=1; }
if grep -qw clean "$work/args" 2>/dev/null; then
  echo "FAIL: Maven was asked for the clean goal: $(cat "$work/args")"; fail=1
fi
[ -f "$work/out/index.html" ] || { echo "FAIL: the new page is missing"; fail=1; }
[ ! -e "$work/out/stale.html" ] || { echo "FAIL: output of an earlier build was kept"; fail=1; }
[ "$fail" = 0 ] && echo PASS
exit "$fail"
