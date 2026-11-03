#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Copies one file from another spec repository at a given ref. An empty ref means
# the highest v0.Y.Z release tag, so specs follow a foundation spec by major version.
# The ref may also be a tag, a branch or a commit SHA.
#
# Usage: fetch-spec-file.sh REPO_URL REF PATH OUT
set -euo pipefail
url=${1:?usage: fetch-spec-file.sh REPO_URL REF PATH OUT}
ref=${2-}
path=${3:?usage: fetch-spec-file.sh REPO_URL REF PATH OUT}
out=${4:?usage: fetch-spec-file.sh REPO_URL REF PATH OUT}
here=$(cd "$(dirname "$0")" && pwd)
if [ -z "$ref" ]; then
  ref=$(bash "$here/resolve-major-tag.sh" "$url" 0)
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work/repo"
git -C "$work/repo" fetch -q --depth 1 "$url" "$ref"
git -C "$work/repo" show "FETCH_HEAD:$path" > "$work/file"
mkdir -p "$(dirname "$out")"
mv "$work/file" "$out"
echo "fetched $path from $url at $ref"
