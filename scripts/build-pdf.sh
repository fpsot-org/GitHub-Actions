#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds a tagged, accessible PDF (PDF/UA-1, PDF/A-2b) from an AsciiDoc book:
# AsciiDoc → DocBook (Asciidoctor) → ODT with a table of contents (pandoc, not kept)
# → PDF (LibreOffice, through odt-to-pdf.py, which fills in the table of contents).
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
toc_title="Contents"
[ "$lang" = fr-CA ] && toc_title="Table des matières"
pandoc -f docbook -t odt --toc --metadata toc-title="$toc_title" --resource-path="$src_dir" --metadata lang="$lang" \
  -o "$work/book.odt" "$work/book.xml"
python3 "$(dirname "$0")/odt-to-pdf.py" "$work/book.odt" "$work/book.pdf" "$work/profile" >"$work/soffice.log" 2>&1 \
  || { cat "$work/soffice.log" >&2; exit 1; }
[ -s "$work/book.pdf" ] || { echo "LibreOffice did not write a PDF" >&2; cat "$work/soffice.log" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
mv "$work/book.pdf" "$out"
