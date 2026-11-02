#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Tests check-pr-commits-signed.sh with a stub gh that returns "<sha> <verified>" lines.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\ncat "$GH_STUB_ANSWER"\n' > "$work/bin/gh"; chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GITHUB_REPOSITORY=fpsot-org/example GH_STUB_ANSWER="$work/answer"
fail=0
printf 'aaaa true\nbbbb true\n' > "$GH_STUB_ANSWER"
bash "$here/check-pr-commits-signed.sh" 7 >/dev/null || { echo "FAIL: all verified should pass"; fail=1; }
printf 'aaaa true\nbbbb false\n' > "$GH_STUB_ANSWER"
out="$(bash "$here/check-pr-commits-signed.sh" 7)"; rc=$?
[ $rc -eq 1 ] || { echo "FAIL: unverified commit should fail, got $rc"; fail=1; }
case "$out" in *bbbb*) ;; *) echo "FAIL: output should name bbbb: $out"; fail=1 ;; esac
: > "$GH_STUB_ANSWER"
bash "$here/check-pr-commits-signed.sh" 7 >/dev/null 2>&1 && { echo "FAIL: no commits should fail"; fail=1; }
[ $fail -eq 0 ] && echo PASS
exit $fail
