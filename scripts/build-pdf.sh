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
# pandoc drops the text alternative of images; keep it, in document order, for
# odt-to-pdf.py to put back (PDF/UA-1 7.3).
python3 -I - "$work/book.xml" >"$work/alts.json" <<'PY'
import json, sys
import xml.etree.ElementTree as ET
ns = {"d": "http://docbook.org/ns/docbook"}
alts = []
kinds = {"{http://docbook.org/ns/docbook}mediaobject", "{http://docbook.org/ns/docbook}inlinemediaobject"}
for media in (e for e in ET.parse(sys.argv[1]).getroot().iter() if e.tag in kinds):
    phrase = media.find("d:textobject/d:phrase", ns)
    alts.append("".join(phrase.itertext()).strip() if phrase is not None else "")
print(json.dumps(alts, ensure_ascii=False))
PY
python3 "$(dirname "$0")/odt-to-pdf.py" "$work/book.odt" "$work/book.pdf" "$work/profile" "$work/alts.json" >"$work/soffice.log" 2>&1 \
  || { cat "$work/soffice.log" >&2; exit 1; }
[ -s "$work/book.pdf" ] || { echo "LibreOffice did not write a PDF" >&2; cat "$work/soffice.log" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
mv "$work/book.pdf" "$out"
