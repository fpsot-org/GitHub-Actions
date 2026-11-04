#!/usr/bin/env bash
# Tests for build-pdf.sh: each test book becomes a tagged PDF/UA-1 and PDF/A-2b file
# with its title and language set, and French accents survive.
# Needs asciidoctor, pandoc, LibreOffice (soffice), poppler-utils and qpdf.
# With VERAPDF_IMAGE set (the veraPDF CLI image), each PDF must also pass veraPDF's
# PDF/UA-1 and PDF/A-2b checks. CONTAINER selects docker (default) or podman.
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
  if [ -n "${VERAPDF_IMAGE:-}" ]; then
    # The veraPDF image runs as a user that is not the owner of the work folder.
    chmod a+rx "$work" && chmod a+r "$pdf"
    for flavour in ua1 2b; do
      result=$(${CONTAINER:-docker} run --rm -v "$work:/data:Z" "$VERAPDF_IMAGE" --format text --flavour "$flavour" "/data/$1.pdf" 2>&1 | tail -1)
      if [[ "$result" != PASS* ]]; then
        echo "FAIL: $1: veraPDF $flavour: $result"; fail=1
        # The rules that failed, from the machine-readable report.
        ${CONTAINER:-docker} run --rm -v "$work:/data:Z" "$VERAPDF_IMAGE" --format mrr --flavour "$flavour" "/data/$1.pdf" 2>/dev/null \
          | grep -o 'clause="[^"]*" testNumber="[^"]*" status="failed"[^>]*' | sed 's/^/  /'
      fi
    done
  fi
  grep -aq "/Lang ($2)" "$work/$1.qdf.pdf" || { echo "FAIL: $1: /Lang ($2) not set"; grep -ao '/Lang ([^)]*)' "$work/$1.qdf.pdf" | head -1; fail=1; }
}
check_pdf en en-CA "FPSOT test specification"
# Asciidoctor turns the apostrophe into a typographic one (U+2019).
check_pdf fr fr-CA "Spécification d’essai FPSOT"
# The table of contents is filled in: its heading and a chapter title come before the chapter text.
if [ -f "$work/en.pdf" ]; then
  pdftotext "$work/en.pdf" - | awk '/This chapter holds one rule/{exit} /^Rules/{n++} END{exit !(n>=2)}' \
    || { echo "FAIL: en: table of contents is empty"; fail=1; }
fi
if [ -f "$work/fr.pdf" ]; then
  pdftotext "$work/fr.pdf" - | grep -q 'Spécification, élément, ça, où, déjà' || { echo "FAIL: fr: accents lost in text"; fail=1; }
fi
[ $fail -eq 0 ] && echo "PASS"
exit $fail
