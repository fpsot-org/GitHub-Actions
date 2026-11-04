#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds the fpsot.org site in parts that run in parallel, then merges them.
# Each spec is its own Roq build ("map"), so no build holds more than one spec's
# pages. The home pages are one more build ("home"). "reduce" merges the parts.
#
# Usage:
#   site-build.sh specs  SITE_DIR                 print each spec repo with its release tag,
#                                                 as a JSON array of {"repo","tag"}
#   site-build.sh map    SITE_DIR REPO TAG OUT_DIR  build one spec at that tag
#   site-build.sh home   SITE_DIR OUT_DIR         build the pages that are not specs
#   site-build.sh reduce OUT_DIR PART_DIR...      merge the parts; a file in two parts fails
# Environment:
#   TOOLS_BIN              folder holding the built tools (map)
#   GH_TOKEN               token for the gh CLI, which lists the releases (specs)
#   FPSOT_SITE_MAVEN_ARGS  Maven options, set by the website builder image
#   SPEC_SOURCE_DIR        folder holding the spec repos, instead of GitHub (tests)
#   MVN                    Maven command (default: mvn)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# Spec repos listed in SITE_DIR/data/specs.yml, one "- repo: NAME" line each. Quotes
# and trailing comments are allowed; any other line fails, so no entry is dropped.
list_specs() {
  local n=0 line name
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%%#*}
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+repo:[[:space:]]*[\"\']?([a-z0-9][a-z0-9._-]*)[\"\']?[[:space:]]*$ ]]; then
      name=${BASH_REMATCH[1]}
      echo "$name"
    else
      echo "error: $1/data/specs.yml:$n: cannot read \"$line\" (want \"- repo: NAME\")" >&2
      return 1
    fi
  done < "$1/data/specs.yml"
}

# The highest vX.Y.Z tag of REPO that has a published GitHub release. A tag without a
# release (its spec-release run failed or never ran) and a pre-release are skipped.
release_tag() {
  gh api "repos/fpsot-org/$1/releases" --paginate \
    --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
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
    repos=$(list_specs "$site") || exit 1
    [ -n "$repos" ] || { echo "error: $site/data/specs.yml lists no spec" >&2; exit 1; }
    json=""
    while read -r r; do
      tag=$(release_tag "$r" || true)
      [ -n "$tag" ] || { echo "error: $r has no release (vX.Y.Z)" >&2; exit 1; }
      json="$json${json:+,}{\"repo\":\"$r\",\"tag\":\"$tag\"}"
    done <<<"$repos"
    echo "[$json]"
    ;;
  map)
    site=$(cd "${1:?usage: site-build.sh map SITE_DIR REPO TAG OUT_DIR}" && pwd)
    repo=${2:?usage: site-build.sh map SITE_DIR REPO TAG OUT_DIR}
    tag=${3:?usage: site-build.sh map SITE_DIR REPO TAG OUT_DIR}
    out=${4:?usage: site-build.sh map SITE_DIR REPO TAG OUT_DIR}
    spec=${repo#fpsot-spec-}
    work=$(mktemp -d)
    trap 'rm -rf "$work"; rm -rf "$site/content/_src/$spec" "$site/content/$spec" "$site/content/fr/$spec" "$site/public/$spec"' EXIT
    src=${SPEC_SOURCE_DIR:-https://github.com/fpsot-org}/$repo
    if ! git clone -q --filter=blob:none --no-checkout "$src" "$work/$repo" 2>"$work/clone.log"; then
      cat "$work/clone.log" >&2
      echo "error: $repo: cannot clone $src" >&2
      exit 1
    fi
    if ! git -C "$work/$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      echo "error: $repo has no tag $tag" >&2
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
