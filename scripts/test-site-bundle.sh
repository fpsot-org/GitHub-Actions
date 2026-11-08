#!/usr/bin/env bash
# Tests site-bundle.sh on the spec-good fixture: the spec's pages land at their site
# URLs with the release version, with PDF_DIR the release PDFs are published and
# linked (and a missing one fails), and a checkout that is not at a tag is refused.
# Needs Go and git.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
(cd "$repo/tools" && go build -o "$work/bin/" ./cmd/...) || exit 1
export TOOLS_BIN="$work/bin"
# A relative term base path must work from any folder.
export TERMBASE="$(realpath --relative-to="$PWD" "$repo/testdata/terms.yaml")"
src="$work/fpsot-spec-good"
cp -r "$repo/testdata/spec-good" "$src"
git -C "$src" init -q
git -C "$src" -c user.name=t -c user.email=t@example.org add -A
git -C "$src" -c user.name=t -c user.email=t@example.org -c commit.gpgsign=false commit -q -m init
git -C "$src" -c user.name=t -c user.email=t@example.org -c tag.gpgsign=false tag -a v0.1.0 -m v0.1.0
git -C "$src" remote add origin git@github.com:fpsot-org/fpsot-spec-good.git
if ! bash "$here/site-bundle.sh" "$src" "$work/content" "$work/public" >"$work/bundle.log" 2>&1; then
  echo "FAIL: site-bundle.sh on a tagged repo:"; cat "$work/bundle.log"; fail=1
fi
for f in good/index.adoc fr/good/index.adoc good/compare/pages/ca/index.adoc fr/good/compare/pages/ca/index.adoc; do
  [ -f "$work/content/$f" ] || { echo "FAIL: $f not written"; fail=1; }
done
grep -q '^:page-version: 0.1.0$' "$work/content/good/index.adoc" 2>/dev/null || { echo "FAIL: version missing"; fail=1; }
grep -q '^:spec-repo-url: https://github.com/fpsot-org/fpsot-spec-good$' "$work/content/good/index.adoc" 2>/dev/null || { echo "FAIL: repo URL not normalised"; fail=1; }
mkdir -p "$work/pdf"
printf '%%PDF-1.7 en' > "$work/pdf/fpsot-spec-good-en.pdf"
printf '%%PDF-1.7 fr!' > "$work/pdf/fpsot-spec-good-fr.pdf"
if ! PDF_DIR="$work/pdf" bash "$here/site-bundle.sh" "$src" "$work/content-pdf" "$work/public-pdf" >"$work/pdf.log" 2>&1; then
  echo "FAIL: site-bundle.sh with PDF_DIR:"; cat "$work/pdf.log"; fail=1
fi
cmp -s "$work/pdf/fpsot-spec-good-en.pdf" "$work/public-pdf/good/fpsot-spec-good-en.pdf" || { echo "FAIL: English PDF not published"; fail=1; }
cmp -s "$work/pdf/fpsot-spec-good-fr.pdf" "$work/public-pdf/fr/good/fpsot-spec-good-fr.pdf" || { echo "FAIL: French PDF not published"; fail=1; }
grep -qx ':page-pdf: /fr/good/fpsot-spec-good-fr.pdf' "$work/content-pdf/fr/good/index.adoc" 2>/dev/null || { echo "FAIL: French page does not link its PDF"; fail=1; }
grep -qx ':page-pdf-other-bytes: 11' "$work/content-pdf/fr/good/index.adoc" 2>/dev/null || { echo "FAIL: French page lacks the English PDF size"; fail=1; }
rm "$work/pdf/fpsot-spec-good-fr.pdf"
if PDF_DIR="$work/pdf" bash "$here/site-bundle.sh" "$src" "$work/content-nopdf" "$work/public-nopdf" >"$work/nopdf.log" 2>&1; then
  echo "FAIL: site-bundle.sh accepted a missing French PDF"; fail=1
fi
grep -q 'fpsot-spec-good-fr.pdf' "$work/nopdf.log" || { echo "FAIL: missing PDF not named:"; cat "$work/nopdf.log"; fail=1; }
git -C "$src" -c user.name=t -c user.email=t@example.org -c commit.gpgsign=false commit -q --allow-empty -m next
if bash "$here/site-bundle.sh" "$src" "$work/content2" >"$work/untagged.log" 2>&1; then
  echo "FAIL: site-bundle.sh accepted a checkout that is not at a tag"; fail=1
fi
grep -q 'not at a release tag' "$work/untagged.log" || { echo "FAIL: message missing:"; cat "$work/untagged.log"; fail=1; }
[ $fail -eq 0 ] && echo "PASS"
exit $fail
