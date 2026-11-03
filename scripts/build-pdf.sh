#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds a tagged, accessible PDF (PDF/UA-1, PDF/A-2b) from an AsciiDoc book:
# AsciiDoc → DocBook (Asciidoctor) → ODT (pandoc, not kept) → PDF (LibreOffice).
# Asciidoctor PDF is not used because it does not produce tagged PDF.
#
# Usage: build-pdf.sh BOOK.adoc OUT.pdf LANG     (LANG: en-CA or fr-CA)
# Extra Asciidoctor attributes can be passed in ASCIIDOCTOR_ATTRS, for example
# ASCIIDOCTOR_ATTRS="-a revnumber=0.1.0".
set -euo pipefail
book=${1:?usage: build-pdf.sh BOOK.adoc OUT.pdf LANG}
out=${2:?usage: build-pdf.sh BOOK.adoc OUT.pdf LANG}
lang=${3:?usage: build-pdf.sh BOOK.adoc OUT.pdf LANG}
case "$lang" in en-CA|fr-CA) ;; *) echo "LANG must be en-CA or fr-CA" >&2; exit 2 ;; esac
src_dir=$(cd "$(dirname "$book")" && pwd)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/build-pdf.XXXXXX")
trap 'rm -rf "$work"' EXIT

# shellcheck disable=SC2086 # ASCIIDOCTOR_ATTRS is a list of options
asciidoctor -b docbook5 -d book --failure-level WARN -a lang="${lang%%-*}" ${ASCIIDOCTOR_ATTRS:-} \
  -o "$work/book.xml" "$book"
pandoc -f docbook -t odt --resource-path="$src_dir" --metadata lang="$lang" \
  -o "$work/book.odt" "$work/book.xml"
filter='pdf:writer_pdf_Export:{"UseTaggedPDF":{"type":"boolean","value":"true"},"PDFUACompliance":{"type":"boolean","value":"true"},"SelectPdfVersion":{"type":"long","value":"2"}}'
soffice --headless "-env:UserInstallation=file://$work/profile" --convert-to "$filter" \
  --outdir "$work" "$work/book.odt" >"$work/soffice.log" 2>&1 || { cat "$work/soffice.log" >&2; exit 1; }
[ -s "$work/book.pdf" ] || { echo "LibreOffice did not write a PDF" >&2; cat "$work/soffice.log" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
mv "$work/book.pdf" "$out"
