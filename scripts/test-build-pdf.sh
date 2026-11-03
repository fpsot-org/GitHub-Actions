#!/usr/bin/env bash
# Tests for build-pdf.sh: each test book becomes a tagged PDF/UA-1 and PDF/A-2b file
# with its title and language set, and French accents survive.
# Needs asciidoctor, pandoc, LibreOffice (soffice), poppler-utils and qpdf.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
check_pdf() { # lang-dir lang-tag title
  pdf="$work/$1.pdf"
  if ! bash "$here/build-pdf.sh" "$here/testdata/book/$1/book.adoc" "$pdf" "$2" >"$work/$1.log" 2>&1; then
    echo "FAIL: $1: build-pdf.sh failed:"; cat "$work/$1.log"; fail=1; return
  fi
  info="$(pdfinfo "$pdf")"
  grep -q '^Tagged: *yes' <<<"$info" || { echo "FAIL: $1: PDF is not tagged"; fail=1; }
  grep -qxF "Title: $3" <<<"$(sed 's/^Title: */Title: /' <<<"$info")" || { echo "FAIL: $1: title is not '$3'"; grep '^Title' <<<"$info"; fail=1; }
  meta="$(pdfinfo -meta "$pdf")"
  grep -q 'pdfuaid:part' <<<"$meta" || { echo "FAIL: $1: no PDF/UA identifier"; fail=1; }
  grep -q 'pdfaid:part' <<<"$meta" || { echo "FAIL: $1: no PDF/A identifier"; fail=1; }
  qpdf --qdf --object-streams=disable "$pdf" "$work/$1.qdf.pdf"
  grep -aq "/Lang ($2)" "$work/$1.qdf.pdf" || { echo "FAIL: $1: /Lang ($2) not set"; grep -ao '/Lang ([^)]*)' "$work/$1.qdf.pdf" | head -1; fail=1; }
}
check_pdf en en-CA "FPSOT test specification"
# Asciidoctor turns the apostrophe into a typographic one (U+2019).
check_pdf fr fr-CA "Spécification d’essai FPSOT"
if [ -f "$work/fr.pdf" ]; then
  pdftotext "$work/fr.pdf" - | grep -q 'Spécification, élément, ça, où, déjà' || { echo "FAIL: fr: accents lost in text"; fail=1; }
fi
[ $fail -eq 0 ] && echo "PASS"
exit $fail
