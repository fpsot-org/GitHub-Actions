#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generates the derived pages of an FPSOT spec repository and checks it. Run it from
# the repository root. Steps run only when the repository needs them:
#   - pages use terms ({abbr-…}, {term-…} or _fpsot-terms.adoc): termgen writes the
#     attribute files and spec/<lang>/glossary.adoc, and checks first use;
#   - jurisdictions/*.yaml exist: LinkML validation (when LINKML is set), then jurisgen
#     writes docs/modules/<lang>/pages/jurisdictions/;
#   - DOC_RULES=true: doccheck.
#
# Environment:
#   TOOLS_BIN  folder holding termgen, jurisgen and doccheck (required)
#   TERMBASE   term base file (required when pages use terms)
#   MODEL      jurisdiction LinkML model (used with LINKML)
#   LINKML     linkml-validate command; validation is skipped when empty
#   STRICT     true: stale comparison rows fail (releases)
#   DOC_RULES  true: run doccheck
set -uo pipefail
: "${TOOLS_BIN:?TOOLS_BIN must point to the built tools}"
status=0
langs=()
for l in en fr; do [ -d "spec/$l" ] && langs+=("$l"); done

if grep -rqE '\{(abbr|term)-|_fpsot-terms\.adoc' spec docs 2>/dev/null; then
  if [ -z "${TERMBASE:-}" ] || [ ! -f "$TERMBASE" ]; then
    echo "error: pages use terms, but no term base was found (TERMBASE='${TERMBASE:-}')"
    exit 1
  fi
  for l in "${langs[@]}"; do
    pages=("spec/$l")
    docs="docs/modules/$l/pages"
    [ -d "$docs" ] && pages+=("$docs")
    "$TOOLS_BIN/termgen" -termbase "$TERMBASE" -lang "$l" -attrs "spec/$l/_fpsot-terms.adoc" \
      -glossary "spec/$l/glossary.adoc" "${pages[@]}" || status=1
    if [ -d "$docs" ]; then
      "$TOOLS_BIN/termgen" -termbase "$TERMBASE" -lang "$l" -attrs "$docs/_fpsot-terms.adoc" \
        -glossary-xref "../../../../spec/$l/glossary.adoc" || status=1
    fi
  done
fi

if compgen -G "jurisdictions/*.yaml" >/dev/null; then
  if [ -n "${LINKML:-}" ]; then
    $LINKML -s "$MODEL" -C Baseline jurisdictions/baseline.yaml || status=1
    mapfile -t jfiles < <(find jurisdictions -name '*.yaml' ! -path jurisdictions/baseline.yaml | sort)
    if [ "${#jfiles[@]}" -gt 0 ]; then
      $LINKML -s "$MODEL" -C JurisdictionFile "${jfiles[@]}" || status=1
    fi
  else
    echo "note: LINKML not set, skipping LinkML validation of jurisdictions/"
  fi
  strict=()
  [ "${STRICT:-false}" = true ] && strict=(-strict)
  for l in "${langs[@]}"; do
    "$TOOLS_BIN/jurisgen" -dir jurisdictions -lang "$l" -out "docs/modules/$l/pages/jurisdictions" "${strict[@]}" || status=1
  done
fi

if [ "${DOC_RULES:-false}" = true ]; then
  "$TOOLS_BIN/doccheck" -root . || status=1
fi
exit $status
