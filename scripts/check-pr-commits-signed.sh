#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Fails unless GitHub verified the signature of every commit in pull request PR.
# Needs GITHUB_REPOSITORY and an authenticated gh.
# Usage: check-pr-commits-signed.sh PR
set -u
pr="${1:?usage: check-pr-commits-signed.sh PR}"
list="$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$pr/commits" --jq '.[] | "\(.sha) \(.commit.verification.verified)"')" || exit 2
if [ -z "$list" ]; then
  echo "pull request $pr has no commits"; exit 1
fi
status=0
while read -r sha verified; do
  if [ "$verified" != "true" ]; then
    echo "commit $sha has no verified signature"
    status=1
  fi
done <<< "$list"
[ $status -eq 0 ] && echo "every commit in pull request $pr has a verified signature"
exit $status
