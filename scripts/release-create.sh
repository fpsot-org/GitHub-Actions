#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Creates the GitHub release of a spec tag, with the PDF books attached. When EXTRA_DIR
# is given, its files are attached too, such as the editable clause modules of the
# procurement spec. Each asset needs its own file name, so a name found twice fails.
#
# Usage: release-create.sh REPO TAG BOOK_DIR [EXTRA_DIR]
#   REPO: owner/name. Needs gh, with GH_TOKEN allowed to write the repo's releases.
set -euo pipefail
usage="usage: release-create.sh REPO TAG BOOK_DIR [EXTRA_DIR]"
repo=${1:?$usage} tag=${2:?$usage} book=${3:?$usage} extra=${4:-}
mapfile -t assets < <(find "$book" -type f -name '*.pdf' 2>/dev/null | LC_ALL=C sort)
if [ -n "$extra" ]; then
  [ -d "$extra" ] || { echo "error: no extra folder $extra" >&2; exit 1; }
  mapfile -t more < <(find "$extra" -type f | LC_ALL=C sort)
  [ "${#more[@]}" -gt 0 ] || { echo "error: the extra folder $extra is empty" >&2; exit 1; }
  assets+=("${more[@]}")
fi
dups=$(for f in "${assets[@]}"; do basename "$f"; done | LC_ALL=C sort | uniq -d)
if [ -n "$dups" ]; then
  echo "error: two assets have the same file name: $dups" >&2
  exit 1
fi
gh release create "$tag" --repo "$repo" --verify-tag --title "$tag" \
  --notes "See CHANGELOG.md for what changed." "${assets[@]}"
