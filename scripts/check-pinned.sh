#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Fails when a workflow uses a third-party action that is not pinned by a full commit SHA.
# Usage: check-pinned.sh PATH...   (files or directories)
set -u
status=0
while IFS= read -r file; do
  while IFS= read -r hit; do
    line="${hit%%:*}"
    ref="$(printf '%s' "${hit#*:}" | sed -E 's/^[[:space:]-]*uses:[[:space:]]*["'\'']?([^"'\''[:space:]#]+).*/\1/')"
    case "$ref" in
      ./*|fpsot-org/*|docker://*) continue ;;
    esac
    sha="${ref##*@}"
    if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
      echo "$file:$line: unpinned action $ref"
      status=1
    fi
  done < <(grep -nE '^[[:space:]-]*uses:' "$file" || true)
done < <(find "$@" -type f \( -name '*.yml' -o -name '*.yaml' \))
exit $status
