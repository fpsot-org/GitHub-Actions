#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Renders every page of an FPSOT spec repository to HTML under OUT_DIR, keeping the
# folder layout. Each written page shows the spec version and the date it last changed
# in Git. Generated pages (glossaries, jurisdiction pages) are rendered together with
# the date of the last commit. Partials (names starting with "_") are not rendered.
# Pages under spec/fr/ and docs/modules/fr/ are marked lang="fr" and use French labels. No page has a
# "Last updated" footer: that time is the checkout time, not the page's date.
#
# Usage: spec-render.sh OUT_DIR
# Environment: SPEC_VERSION (default "unreleased"), CONTRIBUTING_URL,
#              SPEC_REPO_URL (both optional).
set -euo pipefail
out=${1:?usage: spec-render.sh OUT_DIR}
version=${SPEC_VERSION:-unreleased}
common=(--failure-level WARN -R . -D "$out" -a "revnumber=$version" -a 'last-update-label!')
[ -n "${CONTRIBUTING_URL:-}" ] && common+=(-a "contributing-url=$CONTRIBUTING_URL")
[ -n "${SPEC_REPO_URL:-}" ] && common+=(-a "spec-repo-url=$SPEC_REPO_URL")
today=$(git log -1 --format=%cs 2>/dev/null || date -u +%F)

# Language attributes of a page, from its path. The French labels are Asciidoctor's.
lang_attrs() {
  case "$1" in
    spec/fr/*|docs/modules/fr/*) printf '%s\n' -a lang=fr -a 'toc-title=Table des matières' -a table-caption=Tableau \
      -a example-caption=Exemple -a figure-caption=Figure -a note-caption=Note -a tip-caption=Astuce \
      -a important-caption=Important -a warning-caption=Avertissement -a caution-caption=Attention \
      -a appendix-caption=Annexe -a chapter-signifier=Chapitre -a part-signifier=Partie \
      -a 'untitled-label=Sans titre' -a version-label=Version ;;
    *) printf '%s\n' -a lang=en ;;
  esac
}

mapfile -t all < <(find spec docs -name '*.adoc' ! -name '_*' 2>/dev/null | sort)
if [ "${#all[@]}" -eq 0 ]; then echo "no .adoc files found"; exit 1; fi
gen_en=() gen_fr=()
for f in "${all[@]}"; do
  case "$f" in
    */glossary.adoc|*/jurisdictions/*)
      case "$f" in spec/fr/*|docs/modules/fr/*) gen_fr+=("$f") ;; *) gen_en+=("$f") ;; esac ;;
    *)
      date=$(git log -1 --format=%cs -- "$f" 2>/dev/null || true)
      mapfile -t la < <(lang_attrs "$f")
      asciidoctor "${common[@]}" "${la[@]}" -a "revdate=${date:-$today}" "$f"
      ;;
  esac
done
if [ "${#gen_en[@]}" -gt 0 ]; then
  mapfile -t la < <(lang_attrs "${gen_en[0]}")
  asciidoctor "${common[@]}" "${la[@]}" -a "revdate=$today" "${gen_en[@]}"
fi
if [ "${#gen_fr[@]}" -gt 0 ]; then
  mapfile -t la < <(lang_attrs "${gen_fr[0]}")
  asciidoctor "${common[@]}" "${la[@]}" -a "revdate=$today" "${gen_fr[@]}"
fi
