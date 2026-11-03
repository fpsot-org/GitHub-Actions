#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Renders every page of an FPSOT spec repository to HTML under OUT_DIR, keeping the
# folder layout. Each written page shows the spec version and the date it last changed
# in Git. Generated pages (glossaries, jurisdiction pages) are rendered together with
# the date of the last commit. Partials (names starting with "_") are not rendered.
#
# Usage: spec-render.sh OUT_DIR
# Environment: SPEC_VERSION (default "unreleased"), CONTRIBUTING_URL,
#              SPEC_REPO_URL (both optional).
set -euo pipefail
out=${1:?usage: spec-render.sh OUT_DIR}
version=${SPEC_VERSION:-unreleased}
common=(--failure-level WARN -R . -D "$out" -a "revnumber=$version")
[ -n "${CONTRIBUTING_URL:-}" ] && common+=(-a "contributing-url=$CONTRIBUTING_URL")
[ -n "${SPEC_REPO_URL:-}" ] && common+=(-a "spec-repo-url=$SPEC_REPO_URL")
today=$(git log -1 --format=%cs 2>/dev/null || date -u +%F)

mapfile -t all < <(find spec docs -name '*.adoc' ! -name '_*' 2>/dev/null | sort)
if [ "${#all[@]}" -eq 0 ]; then echo "no .adoc files found"; exit 1; fi
generated=()
for f in "${all[@]}"; do
  case "$f" in
    */glossary.adoc|*/jurisdictions/*) generated+=("$f") ;;
    *)
      date=$(git log -1 --format=%cs -- "$f" 2>/dev/null || true)
      asciidoctor "${common[@]}" -a "revdate=${date:-$today}" "$f"
      ;;
  esac
done
if [ "${#generated[@]}" -gt 0 ]; then
  asciidoctor "${common[@]}" -a "revdate=$today" "${generated[@]}"
fi
