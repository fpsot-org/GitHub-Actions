#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Prints the highest vMAJOR.Y.Z release tag of a git repository. Pre-release tags
# (v0.3.0-rc.1) and other tags are ignored. Exits 3 when there is no such tag.
#
# Usage: resolve-major-tag.sh REPO_URL MAJOR
set -euo pipefail
url=${1:?usage: resolve-major-tag.sh REPO_URL MAJOR}
major=${2:?usage: resolve-major-tag.sh REPO_URL MAJOR}
case "$major" in *[!0-9]*|'') echo "MAJOR must be a number" >&2; exit 2 ;; esac
tag=$(git ls-remote --tags --refs "$url" \
  | sed -n "s|^[0-9a-f]*[[:space:]]*refs/tags/\(v$major\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p" \
  | sort -V | tail -n 1)
if [ -z "$tag" ]; then
  echo "no v$major.Y.Z tag in $url" >&2
  exit 3
fi
echo "$tag"
