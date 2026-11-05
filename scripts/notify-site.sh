#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tells the site repo that a spec was released, so the site rebuilds with it.
# It sends a "spec-released" repository_dispatch to fpsot-org/fpsot-org.github.io.
# GH_TOKEN must be a token of the fpsot-ci GitHub App with access to the site repo.
#
# Usage: notify-site.sh [--check]   (--check: only check that the credentials are set)
# Environment: FPSOT_CI_APP_CLIENT_ID (only checked: a release whose notification cannot
# be sent must fail, not pass quietly), GH_TOKEN, REPO (owner/name), TAG.
set -euo pipefail
site=${SITE_REPO:-fpsot-org/fpsot-org.github.io}
if [ -z "${FPSOT_CI_APP_CLIENT_ID:-}" ]; then
  echo "error: FPSOT_CI_APP_CLIENT_ID is not set for this repository, so the site cannot be told about this release" >&2
  exit 1
fi
[ "${1:-}" = --check ] && exit 0
: "${GH_TOKEN:?GH_TOKEN must be the App token}" "${REPO:?REPO must be owner/name}" "${TAG:?TAG must be the release tag}"
gh api "repos/$site/dispatches" -f event_type=spec-released \
  -f "client_payload[repo]=$REPO" -f "client_payload[tag]=$TAG"
echo "notified $site: $REPO $TAG"
