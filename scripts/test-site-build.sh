#!/usr/bin/env bash
# Tests site-build.sh on the site-min fixture: one spec is built on its own (map),
# the home pages on their own (home), and the parts are merged (reduce). A spec
# that does not exist, a spec without a release tag and two parts that hold the
# same file all fail and say why.
# Needs Go, git, Maven and JDK 25: run it in the website builder image.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
# TOOLS_BIN may hold the tools already built, for a run where Go is not installed.
if [ ! -x "${TOOLS_BIN:-}/sitecollect" ]; then
  (cd "$repo/tools" && go build -o "$work/bin/" ./cmd/...) || exit 1
  TOOLS_BIN="$work/bin"
fi
export TOOLS_BIN TERMBASE="$repo/testdata/terms.yaml" SPEC_SOURCE_DIR="$work/repos"
git_t() { git -c user.name=t -c user.email=t@example.org -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
mkdir -p "$work/repos"
cp -r "$repo/testdata/spec-good" "$work/repos/fpsot-spec-good"
git_t -C "$work/repos/fpsot-spec-good" init -q
git_t -C "$work/repos/fpsot-spec-good" add -A
git_t -C "$work/repos/fpsot-spec-good" commit -q -m fixture
git_t -C "$work/repos/fpsot-spec-good" tag -a v0.1.0 -m v0.1.0
cp -r "$repo/testdata/spec-good" "$work/repos/fpsot-spec-untagged"
git_t -C "$work/repos/fpsot-spec-untagged" init -q
git_t -C "$work/repos/fpsot-spec-untagged" add -A
git_t -C "$work/repos/fpsot-spec-untagged" commit -q -m fixture
cp -r "$repo/testdata/site-min" "$work/site"
# The fixture lists a real spec for the CI run; here it builds the local fixture spec.
printf -- '- repo: fpsot-spec-good\n' > "$work/site/data/specs.yml"

specs=$(bash "$here/site-build.sh" specs "$work/site")
[ "$specs" = '["fpsot-spec-good"]' ] || { echo "FAIL: specs printed $specs"; fail=1; }

if ! bash "$here/site-build.sh" map "$work/site" fpsot-spec-good "$work/part-good" >"$work/map.log" 2>&1; then
  echo "FAIL: map:"; tail -30 "$work/map.log"; fail=1
fi
for f in good/index.html fr/good/index.html fr/good/compare/pages/ca/index.html; do
  [ -f "$work/part-good/$f" ] || { echo "FAIL: map did not write $f"; fail=1; }
done
[ ! -e "$work/part-good/index.html" ] || { echo "FAIL: map wrote the home page"; fail=1; }
grep -q '<html lang="fr"' "$work/part-good/fr/good/index.html" 2>/dev/null || { echo "FAIL: French spec page is not lang fr"; fail=1; }

if ! bash "$here/site-build.sh" home "$work/site" "$work/part-home" >"$work/home.log" 2>&1; then
  echo "FAIL: home:"; tail -30 "$work/home.log"; fail=1
fi
[ -f "$work/part-home/index.html" ] && [ -f "$work/part-home/fr/index.html" ] || { echo "FAIL: home pages missing"; fail=1; }
[ ! -e "$work/part-home/good" ] || { echo "FAIL: home holds a spec"; fail=1; }

if ! bash "$here/site-build.sh" reduce "$work/out" "$work/part-home" "$work/part-good" >"$work/reduce.log" 2>&1; then
  echo "FAIL: reduce:"; cat "$work/reduce.log"; fail=1
fi
[ -f "$work/out/index.html" ] && [ -f "$work/out/good/index.html" ] || { echo "FAIL: reduce lost a part"; fail=1; }
mkdir -p "$work/part-dup/good" && echo dup > "$work/part-dup/good/index.html"
if bash "$here/site-build.sh" reduce "$work/out2" "$work/part-good" "$work/part-dup" >"$work/dup.log" 2>&1; then
  echo "FAIL: reduce accepted two parts with the same file"; fail=1
fi
grep -q 'part-good' "$work/dup.log" && grep -q 'part-dup' "$work/dup.log" || { echo "FAIL: conflict message does not name both parts:"; cat "$work/dup.log"; fail=1; }

if bash "$here/site-build.sh" map "$work/site" fpsot-spec-nope "$work/part-nope" >"$work/nope.log" 2>&1; then
  echo "FAIL: map accepted a spec that does not exist"; fail=1
fi
grep -q 'fpsot-spec-nope' "$work/nope.log" || { echo "FAIL: missing spec not named"; fail=1; }
if bash "$here/site-build.sh" map "$work/site" fpsot-spec-untagged "$work/part-untagged" >"$work/untagged.log" 2>&1; then
  echo "FAIL: map accepted a spec without a release tag"; fail=1
fi
grep -q 'no release tag' "$work/untagged.log" || { echo "FAIL: no-tag message missing:"; cat "$work/untagged.log"; fail=1; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
