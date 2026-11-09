#!/usr/bin/env bash
# Tests spec-pdfs.sh on the spec-good fixture: one PDF per language, named after the
# repo, with the legal notice of the release on page 2.
# Needs Go, asciidoctor, pandoc, LibreOffice (soffice), poppler-utils and pikepdf.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
(cd "$repo/tools" && go build -buildvcs=false -o "$work/bin/" ./cmd/...) || exit 1
cp -r "$repo/testdata/spec-good" "$work/spec"
(cd "$work/spec" && TOOLS_BIN="$work/bin" TERMBASE="$repo/testdata/terms.yaml" bash "$here/spec-generate.sh") >"$work/gen.log" 2>&1 \
  || { echo "FAIL: spec-generate.sh:"; cat "$work/gen.log"; exit 1; }
src=https://github.com/fpsot-org/fpsot-spec-good/tree/v0.1.0
if ! bash "$here/spec-pdfs.sh" "$work/spec" "$work/out" fpsot-spec-good 0.1.0 2026-11-05 "$src" >"$work/pdfs.log" 2>&1; then
  echo "FAIL: spec-pdfs.sh:"; cat "$work/pdfs.log"; fail=1
fi
for l in en fr; do
  pdf="$work/out/fpsot-spec-good-$l.pdf"
  [ -s "$pdf" ] || { echo "FAIL: $l PDF not written"; fail=1; continue; }
  page=$(pdftotext -f 2 -l 2 "$pdf" -)
  want="Version 0.1.0, released 2026-11-05"; [ "$l" = fr ] && want="Version 0.1.0, publiée le 2026-11-05"
  grep -qF "$want" <<<"$page" || { echo "FAIL: $l: no version and date on page 2:"; head -5 <<<"$page"; fail=1; }
  grep -qF "$src" <<<"$page" || { echo "FAIL: $l: no source URL on page 2"; fail=1; }
done
[ $fail -eq 0 ] && echo "PASS"
exit $fail
