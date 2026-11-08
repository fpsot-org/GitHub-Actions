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
#   site-build.sh map    SITE_DIR REPO TAG OUT_DIR  build one spec at that tag, with the
#                                                 release PDFs of that tag
#   site-build.sh book   OUT_DIR REPO TAG [REPO TAG]...  build one PDF per language,
#                                                 fpsot-specifications-<lang>.pdf, that holds
#                                                 every spec given, each as a part
#   site-build.sh home   SITE_DIR OUT_DIR [BOOK_DIR]  build the pages that are not specs,
#                                                 with the book's PDFs from BOOK_DIR
#   site-build.sh reduce OUT_DIR PART_DIR...      merge the parts; a file in two parts fails
# Environment:
#   TOOLS_BIN              folder holding the built tools (map, book)
#   TERMBASE               term base file (map, book; default: the repo's own, else
#                          fpsot-spec-writing's highest v0 release)
#   SITE_URL               URL of the site, for links to guides in the book
#   GH_TOKEN               token for the gh CLI, which lists the releases (specs) and
#                          downloads their PDFs (map)
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

# Clones REPO into DIR, checked out at TAG.
clone_at_tag() {
  local src=${SPEC_SOURCE_DIR:-https://github.com/fpsot-org}/$1
  if ! git clone -q --filter=blob:none --no-checkout "$src" "$3" 2>"$3.clone.log"; then
    cat "$3.clone.log" >&2
    echo "error: $1: cannot clone $src" >&2
    return 1
  fi
  if ! git -C "$3" rev-parse -q --verify "refs/tags/$2" >/dev/null; then
    echo "error: $1 has no tag $2" >&2
    return 1
  fi
  git -C "$3" checkout -q "$2"
}

# Checks that a repo name is fpsot-spec-<name>, lower-case, and <name> is not reserved.
check_repo_name() {
  if ! [[ $1 =~ ^fpsot-spec-[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ "${1#fpsot-spec-}" = fr ]; then
    echo "error: '$1' is not a valid spec repo name (fpsot-spec-<name>, lower-case, not 'fr')" >&2
    return 1
  fi
}

# Runs the Roq build of SITE_DIR into SITE_DIR/target/roq.
roq_build() {
  # shellcheck disable=SC2086 # FPSOT_SITE_MAVEN_ARGS holds several options
  (cd "$1" && QUARKUS_ROQ_GENERATOR_BATCH=true ${MVN:-mvn} -B -q ${FPSOT_SITE_MAVEN_ARGS:-} clean package quarkus:run)
}

cmd=${1:?usage: site-build.sh specs|map|book|home|reduce ...}
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
    # The cleanup below deletes folders named after the spec, so an empty or reserved
    # name would delete home content. Refuse it before touching anything.
    check_repo_name "$repo" || exit 1
    work=$(mktemp -d)
    trap 'rm -rf "$work"; rm -rf "$site/content/_src/$spec" "$site/content/$spec" "$site/content/fr/$spec" "$site/public/$spec" "$site/public/fr/$spec"' EXIT
    clone_at_tag "$repo" "$tag" "$work/$repo" || exit 1
    # The PDFs of this release, served from the site next to each language's pages.
    mkdir -p "$work/pdf"
    names=() patterns=()
    for l in en fr; do
      if [ -d "$work/$repo/spec/$l" ]; then names+=("$repo-$l.pdf"); patterns+=(--pattern "$repo-$l.pdf"); fi
    done
    if [ ${#names[@]} -gt 0 ] && ! gh release download "$tag" --repo "fpsot-org/$repo" "${patterns[@]}" --dir "$work/pdf" 2>"$work/pdf.log"; then
      cat "$work/pdf.log" >&2
    fi
    for f in "${names[@]}"; do
      [ -s "$work/pdf/$f" ] || { echo "error: $repo $tag: the release has no $f" >&2; exit 1; }
    done
    PDF_DIR="$work/pdf" bash "$here/site-bundle.sh" "$work/$repo" "$site/content" "$site/public" \
      || { echo "error: $repo: collecting the pages failed" >&2; exit 1; }
    roq_build "$site" || { echo "error: $repo: the Roq build failed" >&2; exit 1; }
    mkdir -p "$out/fr"
    cp -r "$site/target/roq/$spec" "$out/"
    cp -r "$site/target/roq/fr/$spec" "$out/fr/"
    echo "site-build: $repo $tag: $(find "$out" -name index.html | wc -l) pages" >&2
    ;;
  book)
    out=${1:?usage: site-build.sh book OUT_DIR REPO TAG [REPO TAG]...}
    shift
    if [ $# -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then
      echo "usage: site-build.sh book OUT_DIR REPO TAG [REPO TAG]..." >&2
      exit 2
    fi
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/specs"
    parts=()
    while [ $# -gt 0 ]; do
      repo=$1 tag=$2
      shift 2
      check_repo_name "$repo" || exit 1
      dir="$work/specs/$repo"
      clone_at_tag "$repo" "$tag" "$dir" || exit 1
      for l in en fr; do
        [ -f "$dir/spec/$l/book.adoc" ] || { echo "error: $repo $tag has no spec/$l/book.adoc" >&2; exit 1; }
      done
      # The glossaries and term attributes, from the same term base as the site pages.
      if [ -n "${TERMBASE:-}" ]; then termbase=$(cd "$(dirname "$TERMBASE")" && pwd)/$(basename "$TERMBASE")
      elif [ -f "$dir/termbase/terms.yaml" ]; then termbase="$dir/termbase/terms.yaml"
      else
        termbase="$work/terms.yaml"
        [ -f "$termbase" ] || bash "$here/fetch-spec-file.sh" https://github.com/fpsot-org/fpsot-spec-writing.git "" termbase/terms.yaml "$termbase" >&2
      fi
      (cd "$dir" && TERMBASE="$termbase" STRICT=false DOC_RULES=false LINKML="" bash "$here/spec-generate.sh") >&2 \
        || { echo "error: $repo: generating the pages failed" >&2; exit 1; }
      parts+=("$dir" "${repo#fpsot-spec-}" "${tag#v}")
    done
    mkdir -p "$out"
    for l in en fr; do
      title="FPSOT specifications" lang=en-US
      [ "$l" = fr ] && title="Spécifications FPSOT" lang=fr-CA
      python3 -I "$here/book-combine.py" "$work/book-$l.adoc" "$l" "$title" "${SITE_URL:-https://fpsot.org}" "${parts[@]}" || exit 1
      # build-pdf.sh fails on any Asciidoctor warning, such as an ID used twice; this
      # first pass also checks that every link leads somewhere.
      asciidoctor -b docbook5 -d book --failure-level WARN -a lang="$l" -o "$work/check-$l.xml" "$work/book-$l.adoc" \
        || { echo "error: the $l book has warnings" >&2; exit 1; }
      python3 -I "$here/book-links.py" "$work/check-$l.xml" || { echo "error: the $l book has links that lead nowhere" >&2; exit 1; }
      bash "$here/build-pdf.sh" "$work/book-$l.adoc" "$out/fpsot-specifications-$l.pdf" "$lang" \
        || { echo "error: the $l PDF build failed" >&2; exit 1; }
    done
    echo "site-build: book of $((${#parts[@]} / 3)) specs: $(cd "$out" && du -h fpsot-specifications-*.pdf | tr '\n' ' ')" >&2
    ;;
  home)
    site=$(cd "${1:?usage: site-build.sh home SITE_DIR OUT_DIR [BOOK_DIR]}" && pwd)
    out=${2:?usage: site-build.sh home SITE_DIR OUT_DIR [BOOK_DIR]}
    book=${3:-}
    if [ -n "$book" ]; then
      # The combined book, at /fpsot-specifications-en.pdf and /fr/fpsot-specifications-fr.pdf.
      # The home pages read the size of each from fpsot.book.<lang>-bytes.
      trap 'rm -f "$site/public/fpsot-specifications-en.pdf" "$site/public/fr/fpsot-specifications-fr.pdf"' EXIT
      for l in en fr; do
        pdf="$book/fpsot-specifications-$l.pdf"
        [ -s "$pdf" ] || { echo "error: the book folder $book has no fpsot-specifications-$l.pdf" >&2; exit 1; }
        dest="$site/public"
        [ "$l" = fr ] && dest="$site/public/fr"
        mkdir -p "$dest"
        cp "$pdf" "$dest/"
        export "FPSOT_BOOK_${l^^}_BYTES=$(wc -c <"$pdf")"
      done
    fi
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
    done | LC_ALL=C sort > "$list"
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
    echo "usage: site-build.sh specs|map|book|home|reduce ..." >&2
    exit 2
    ;;
esac
