#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds the PDF books of a generated spec repository, one per language that has
# spec/<lang>/book.adoc, as OUT_DIR/<NAME>-<lang>.pdf: tagged PDF/UA-1 and PDF/A-2b,
# with the legal notice of the release after the title page (spec-legal.py).
#
# Usage: spec-pdfs.sh REPO_DIR OUT_DIR NAME VERSION DATE SOURCE_URL
#   NAME: the repo name, such as fpsot-spec-vcs. VERSION: such as 0.1.0, or
#   "unreleased". DATE: the release date, YYYY-MM-DD. SOURCE_URL: the sources at
#   that version, such as https://github.com/fpsot-org/fpsot-spec-vcs/tree/v0.1.0.
set -euo pipefail
usage="usage: spec-pdfs.sh REPO_DIR OUT_DIR NAME VERSION DATE SOURCE_URL"
repo=$(cd "${1:?$usage}" && pwd)
out=${2:?$usage} name=${3:?$usage} version=${4:?$usage} date=${5:?$usage} source=${6:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/spec-pdfs.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
n=0
for l in en fr; do
  [ -f "$repo/spec/$l/book.adoc" ] || continue
  tag=en-US
  [ "$l" = fr ] && tag=fr-CA
  python3 -I "$here/spec-legal.py" spec "$repo" "$l" "$version" "$date" "$source" > "$work/notice-$l.json"
  ASCIIDOCTOR_ATTRS="-a revnumber=$version" PDF_NOTICE="$work/notice-$l.json" \
    bash "$here/build-pdf.sh" "$repo/spec/$l/book.adoc" "$out/$name-$l.pdf" "$tag"
  pdfinfo "$out/$name-$l.pdf" | grep -q '^Tagged: *yes' || { echo "error: $name-$l.pdf is not tagged" >&2; exit 1; }
  n=$((n + 1))
done
[ $n -gt 0 ] || { echo "error: $repo has no spec/<lang>/book.adoc" >&2; exit 1; }
