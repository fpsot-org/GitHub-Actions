#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Checks that TAG is an annotated vX.Y.Z tag whose signature GitHub verified.
# Run inside a clone that has the tag. Needs GITHUB_REPOSITORY and an authenticated gh.
# Usage: check-release-tag.sh TAG
set -u
tag="${1:-}"
if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "tag '$tag' is not named vX.Y.Z"; exit 1
fi
if [ "$(git cat-file -t "$tag" 2>/dev/null)" != "tag" ]; then
  echo "tag $tag is not an annotated tag"; exit 1
fi
sha="$(git rev-parse "$tag")"
verified="$(gh api "repos/$GITHUB_REPOSITORY/git/tags/$sha" --jq .verification.verified)"
if [ "$verified" != "true" ]; then
  echo "GitHub did not verify the signature of tag $tag"; exit 1
fi
echo "tag $tag is annotated and its signature is verified"
