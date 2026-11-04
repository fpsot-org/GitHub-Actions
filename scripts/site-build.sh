#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds the fpsot.org site in parts that run in parallel, then merges them.
# Each spec is its own Roq build ("map"), so no build holds more than one spec's
# pages. The home pages are one more build ("home"). "reduce" merges the parts.
#
# Usage:
#   site-build.sh specs  SITE_DIR                 print the spec repos as a JSON array
#   site-build.sh map    SITE_DIR REPO OUT_DIR    build one spec at its highest release tag
#   site-build.sh home   SITE_DIR OUT_DIR         build the pages that are not specs
#   site-build.sh reduce OUT_DIR PART_DIR...      merge the parts; a file in two parts fails
# Environment:
#   TOOLS_BIN              folder holding the built tools (map)
#   FPSOT_SITE_MAVEN_ARGS  Maven options, set by the website builder image
#   SPEC_SOURCE_DIR        folder holding the spec repos, instead of GitHub (tests)
#   MVN                    Maven command (default: mvn)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# Spec repos listed in SITE_DIR/data/specs.yml, as "- repo: NAME" lines.
list_specs() {
  sed -n 's/^[[:space:]]*-[[:space:]]*repo:[[:space:]]*\([A-Za-z0-9._-]*\)[[:space:]]*$/\1/p' "$1/data/specs.yml"
}

# Runs the Roq build of SITE_DIR into SITE_DIR/target/roq.
roq_build() {
  # shellcheck disable=SC2086 # FPSOT_SITE_MAVEN_ARGS holds several options
  (cd "$1" && QUARKUS_ROQ_GENERATOR_BATCH=true ${MVN:-mvn} -B -q ${FPSOT_SITE_MAVEN_ARGS:-} clean package quarkus:run)
}

cmd=${1:?usage: site-build.sh specs|map|home|reduce ...}
shift
case "$cmd" in
  specs)
    site=${1:?usage: site-build.sh specs SITE_DIR}
    json=""
    while read -r r; do json="$json${json:+,}\"$r\""; done < <(list_specs "$site")
    echo "[$json]"
    ;;
  map)
    site=$(cd "${1:?usage: site-build.sh map SITE_DIR REPO OUT_DIR}" && pwd)
    repo=${2:?usage: site-build.sh map SITE_DIR REPO OUT_DIR}
    out=${3:?usage: site-build.sh map SITE_DIR REPO OUT_DIR}
    spec=${repo#fpsot-spec-}
    work=$(mktemp -d)
    trap 'rm -rf "$work"; rm -rf "$site/content/_src/$spec" "$site/content/$spec" "$site/content/fr/$spec" "$site/public/$spec"' EXIT
    src=${SPEC_SOURCE_DIR:-https://github.com/fpsot-org}/$repo
    if ! git clone -q --filter=blob:none --no-checkout "$src" "$work/$repo" 2>"$work/clone.log"; then
      cat "$work/clone.log" >&2
      echo "error: $repo: cannot clone $src" >&2
      exit 1
    fi
    tag=$(git -C "$work/$repo" tag -l 'v*.*.*' --sort=-v:refname | head -1)
    if [ -z "$tag" ]; then
      echo "error: $repo has no release tag (vX.Y.Z)" >&2
      exit 1
    fi
    git -C "$work/$repo" checkout -q "$tag"
    # The origin must be the GitHub repo, for the links to it on each page.
    git -C "$work/$repo" remote set-url origin "https://github.com/fpsot-org/$repo"
    bash "$here/site-bundle.sh" "$work/$repo" "$site/content" "$site/public" \
      || { echo "error: $repo: collecting the pages failed" >&2; exit 1; }
    roq_build "$site" || { echo "error: $repo: the Roq build failed" >&2; exit 1; }
    mkdir -p "$out/fr"
    cp -r "$site/target/roq/$spec" "$out/"
    cp -r "$site/target/roq/fr/$spec" "$out/fr/"
    echo "site-build: $repo $tag: $(find "$out" -name index.html | wc -l) pages" >&2
    ;;
  home)
    site=$(cd "${1:?usage: site-build.sh home SITE_DIR OUT_DIR}" && pwd)
    out=${2:?usage: site-build.sh home SITE_DIR OUT_DIR}
    roq_build "$site" || { echo "error: the home build failed" >&2; exit 1; }
    mkdir -p "$out"
    cp -r "$site/target/roq/." "$out/"
    ;;
  reduce)
    out=${1:?usage: site-build.sh reduce OUT_DIR PART_DIR...}
    shift
    [ $# -gt 0 ] || { echo "usage: site-build.sh reduce OUT_DIR PART_DIR..." >&2; exit 2; }
    list=$(mktemp)
    trap 'rm -f "$list"' EXIT
    for part in "$@"; do
      (cd "$part" && find . -type f | sed "s|^\./||; s|\$|\t$part|")
    done | sort > "$list"
    conflicts=$(cut -f1 "$list" | uniq -d)
    if [ -n "$conflicts" ]; then
      while read -r f; do
        printf '%s is in more than one part: %s\n' "$f" "$(awk -F'\t' -v f="$f" '$1 == f { printf "%s ", $2 }' "$list")" >&2
      done <<<"$conflicts"
      exit 1
    fi
    mkdir -p "$out"
    for part in "$@"; do cp -r "$part/." "$out/"; done
    echo "site-build: merged $# parts, $(wc -l < "$list") files" >&2
    ;;
  *)
    echo "usage: site-build.sh specs|map|home|reduce ..." >&2
    exit 2
    ;;
esac
