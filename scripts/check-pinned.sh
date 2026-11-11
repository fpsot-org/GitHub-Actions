#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Fails when a workflow uses a third-party action that is not pinned by a full commit SHA,
# or when the same image is pinned by more than one digest across the workflows.
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
while IFS= read -r image; do
  echo "$image is pinned to more than one digest:"
  find "$@" -type f \( -name '*.yml' -o -name '*.yaml' \) -exec grep -nHF "$image@sha256:" {} + | sed 's/^/  /'
  status=1
done < <(find "$@" -type f \( -name '*.yml' -o -name '*.yaml' \) -exec grep -ohE '[A-Za-z0-9._/-]+@sha256:[0-9a-f]{64}' {} + \
  | sort -u | sed 's/@sha256:.*//' | uniq -d)
exit $status
