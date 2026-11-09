#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Replaces the PDF books of an existing spec release with rebuilt ones, and adds a
# note to its release notes, in English and French. Running it again replaces the
# note instead of adding a second one. The tag and the specification text do not
# change: only the PDF assets do.
#
# Usage: release-pdfs.sh REPO TAG PDF_DIR
#   REPO: such as fpsot-spec-vcs, in fpsot-org. PDF_DIR holds <REPO>-en.pdf and
#   <REPO>-fr.pdf. Needs gh, with GH_TOKEN allowed to write the repo's releases.
set -euo pipefail
usage="usage: release-pdfs.sh REPO TAG PDF_DIR"
repo=${1:?$usage} tag=${2:?$usage} dir=${3:?$usage}
marker="<!-- fpsot-pdf-refresh -->"
pdfs=()
for l in en fr; do
  [ -s "$dir/$repo-$l.pdf" ] || { echo "error: $dir has no $repo-$l.pdf" >&2; exit 1; }
  pdfs+=("$dir/$repo-$l.pdf")
done
if ! body=$(gh release view "$tag" --repo "fpsot-org/$repo" --json body -q .body); then
  echo "error: fpsot-org/$repo has no release $tag" >&2
  exit 1
fi
gh release upload "$tag" --repo "fpsot-org/$repo" --clobber "${pdfs[@]}"
today=$(date -u +%F)
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
# The text before an earlier note, without its trailing blank lines, then this run's note.
before=${body%%"$marker"*}
before=${before%"${before##*[![:space:]]}"}
{
  printf '%s\n\n%s\n' "$before" "$marker"
  echo "The PDF books were rebuilt on $today, with a page for the copyright and license notice. The specification text is the same as at $tag."
  echo
  echo "Les livres PDF ont été reconstruits le $today, avec une page pour la mention de droit d’auteur et de licence. Le texte de la spécification est le même qu’à $tag."
} > "$notes"
gh release edit "$tag" --repo "fpsot-org/$repo" --notes-file "$notes"
echo "release-pdfs: fpsot-org/$repo $tag: PDFs replaced, note added" >&2
