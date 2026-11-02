#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Tests check-release-tag.sh with a stub gh that answers the GitHub verification call.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
cat "$GH_STUB_ANSWER"
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GITHUB_REPOSITORY=fpsot-org/example GH_STUB_ANSWER="$work/answer"
git -C "$work" init -q repo && cd "$work/repo" && git -c user.name=t -c user.email=t@example.org commit -q --allow-empty -m init
git -c user.name=t -c user.email=t@example.org tag -a v1.0.0 -m $'release\n-----BEGIN SSH SIGNATURE-----\nx'
git tag v1.0.1
git -c user.name=t -c user.email=t@example.org tag -a 1.0.2 -m x
fail=0
expect() { # expect CODE TAG ANSWER
  echo "$3" > "$GH_STUB_ANSWER"
  bash "$here/check-release-tag.sh" "$2" >/dev/null 2>&1; rc=$?
  [ $rc -eq "$1" ] || { echo "FAIL: $2 with gh=$3 gave $rc, want $1"; fail=1; }
}
expect 1 v1.0.0 false   # fake signature marker in the message, GitHub says unverified
expect 0 v1.0.0 true    # GitHub verified the signature
expect 1 v1.0.1 true    # lightweight tag
expect 1 1.0.2 true     # wrong name
[ $fail -eq 0 ] && echo PASS
exit $fail
