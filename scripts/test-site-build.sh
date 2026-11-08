#!/usr/bin/env bash
# Tests site-build.sh on the site-min fixture: one spec is built on its own (map),
# the home pages on their own (home), and the parts are merged (reduce). A spec
# that does not exist, a spec without a release tag, a release without its PDFs and
# two parts that hold the same file all fail and say why. map publishes the
# release PDFs of the spec, one in each language's folder.
# Needs Go, git, Maven and JDK 25: run it in the website builder image.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Run from the work folder, so a relative path never writes into the repo.
cd "$work"
fail=0
# TOOLS_BIN may hold the tools already built, for a run where Go is not installed.
if [ ! -x "${TOOLS_BIN:-}/sitecollect" ]; then
  (cd "$repo/tools" && go build -buildvcs=false -o "$work/bin/" ./cmd/...) || exit 1
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
# The published releases, as a fake gh prints them: v0.2.0 has a tag but no release,
# and v0.3.0-rc.1 is a pre-release, so the site must take v0.1.0.
git_t -C "$work/repos/fpsot-spec-good" tag -a v0.2.0 -m v0.2.0
git_t -C "$work/repos/fpsot-spec-good" tag -a v0.3.0-rc.1 -m v0.3.0-rc.1
mkdir -p "$work/fakebin"
# The release assets, as "gh release download TAG --repo fpsot-org/REPO --pattern F
# ... --dir D" finds them: $work/assets/REPO/TAG/F.
mkdir -p "$work/assets/fpsot-spec-good/v0.1.0" "$work/assets/fpsot-spec-nopdf/v0.1.0"
printf '%%PDF-1.7 good en' > "$work/assets/fpsot-spec-good/v0.1.0/fpsot-spec-good-en.pdf"
printf '%%PDF-1.7 good fr' > "$work/assets/fpsot-spec-good/v0.1.0/fpsot-spec-good-fr.pdf"
printf '%%PDF-1.7 nopdf en' > "$work/assets/fpsot-spec-nopdf/v0.1.0/fpsot-spec-nopdf-en.pdf"
cat > "$work/fakebin/gh" <<GH
#!/usr/bin/env bash
assets="$work/assets"
GH
cat >> "$work/fakebin/gh" <<'GH'
case "$*" in
  *fpsot-spec-good/releases*) printf 'v0.1.0\nv0.3.0-rc.1\n'; exit 0 ;;
esac
if [ "$1 $2" = "release download" ]; then
  tag=$3; shift 3; repo="" dir=. pats=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo=${2#fpsot-org/}; shift 2 ;;
      --pattern) pats+=("$2"); shift 2 ;;
      --dir) dir=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -d "$assets/$repo/$tag" ] || { echo "release not found" >&2; exit 1; }
  mkdir -p "$dir"
  n=0
  for p in "${pats[@]}"; do
    if [ -f "$assets/$repo/$tag/$p" ]; then cp "$assets/$repo/$tag/$p" "$dir/"; n=$((n + 1)); fi
  done
  [ $n -gt 0 ] || { echo "no assets match the file pattern" >&2; exit 1; }
fi
GH
chmod +x "$work/fakebin/gh"
specs() { # specs.yml content -> output of "site-build.sh specs"
  printf '%s' "$1" > "$work/site/data/specs.yml"
  PATH="$work/fakebin:$PATH" bash "$here/site-build.sh" specs "$work/site"
}
out=$(specs $'# Specs.\n- repo: fpsot-spec-good\n')
[ "$out" = '[{"repo":"fpsot-spec-good","tag":"v0.1.0"}]' ] || { echo "FAIL: specs printed $out"; fail=1; }
out=$(specs $'- repo: "fpsot-spec-good"  # quoted, with a comment\n')
[ "$out" = '[{"repo":"fpsot-spec-good","tag":"v0.1.0"}]' ] || { echo "FAIL: quoted entry: $out"; fail=1; }
if out=$(specs $'- repo: fpsot-spec-good\n- name: fpsot-spec-other\n' 2>&1); then
  echo "FAIL: specs accepted a line it cannot read"; fail=1
fi
grep -q 'name: fpsot-spec-other' <<<"$out" || { echo "FAIL: unreadable line not named: $out"; fail=1; }
if out=$(specs $'# nothing\n' 2>&1); then echo "FAIL: specs accepted an empty list"; fail=1; fi
if out=$(specs $'- repo: fpsot-spec-untagged\n' 2>&1); then echo "FAIL: specs accepted a spec without a release"; fail=1; fi
grep -q 'fpsot-spec-untagged has no release' <<<"$out" || { echo "FAIL: no-release message missing: $out"; fail=1; }
printf -- '- repo: fpsot-spec-good\n' > "$work/site/data/specs.yml"

export PATH="$work/fakebin:$PATH"
if ! bash "$here/site-build.sh" map "$work/site" fpsot-spec-good v0.1.0 "$work/part-good" >"$work/map.log" 2>&1; then
  echo "FAIL: map:"; tail -30 "$work/map.log"; fail=1
fi
for f in good/index.html fr/good/index.html fr/good/compare/pages/ca/index.html; do
  [ -f "$work/part-good/$f" ] || { echo "FAIL: map did not write $f"; fail=1; }
done
[ ! -e "$work/part-good/index.html" ] || { echo "FAIL: map wrote the home page"; fail=1; }
grep -q '<html lang="fr"' "$work/part-good/fr/good/index.html" 2>/dev/null || { echo "FAIL: French spec page is not lang fr"; fail=1; }
cmp -s "$work/assets/fpsot-spec-good/v0.1.0/fpsot-spec-good-en.pdf" "$work/part-good/good/fpsot-spec-good-en.pdf" || { echo "FAIL: map did not publish the English PDF in /good/"; fail=1; }
cmp -s "$work/assets/fpsot-spec-good/v0.1.0/fpsot-spec-good-fr.pdf" "$work/part-good/fr/good/fpsot-spec-good-fr.pdf" || { echo "FAIL: map did not publish the French PDF in /fr/good/"; fail=1; }
[ ! -e "$work/site/public/fr/good" ] && [ ! -e "$work/site/public/good" ] || { echo "FAIL: map left the PDFs in the site folder"; fail=1; }
# A release without its French PDF fails, and says which file is missing.
cp -r "$work/repos/fpsot-spec-good" "$work/repos/fpsot-spec-nopdf"
if bash "$here/site-build.sh" map "$work/site" fpsot-spec-nopdf v0.1.0 "$work/part-nopdf" >"$work/nopdf.log" 2>&1; then
  echo "FAIL: map accepted a release without its French PDF"; fail=1
fi
grep -q 'fpsot-spec-nopdf-fr.pdf' "$work/nopdf.log" || { echo "FAIL: missing PDF not named:"; tail -5 "$work/nopdf.log"; fail=1; }

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

if bash "$here/site-build.sh" map "$work/site" fpsot-spec-nope v0.1.0 "$work/part-nope" >"$work/nope.log" 2>&1; then
  echo "FAIL: map accepted a spec that does not exist"; fail=1
fi
grep -q 'fpsot-spec-nope' "$work/nope.log" || { echo "FAIL: missing spec not named"; fail=1; }
if bash "$here/site-build.sh" map "$work/site" fpsot-spec-good v9.9.9 "$work/part-v9" >"$work/v9.log" 2>&1; then
  echo "FAIL: map accepted a tag that does not exist"; fail=1
fi
grep -q 'v9.9.9' "$work/v9.log" || { echo "FAIL: missing tag not named:"; cat "$work/v9.log"; fail=1; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
