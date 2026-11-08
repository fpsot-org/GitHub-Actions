#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Turns one spec repository, checked out at a release tag with its history, into
# content for the fpsot.org site. It generates the derived pages (glossaries,
# comparison pages) and runs sitecollect, which writes each page at its site URL.
# The release already ran the strict checks, so this step does not repeat them.
#
# Usage: site-bundle.sh REPO_DIR CONTENT_DIR [PUBLIC_DIR]
# Environment:
#   TOOLS_BIN  folder holding termgen, jurisgen, doccheck and sitecollect (required)
#   TERMBASE   term base file (default: the repo's own, else fpsot-spec-writing's
#              highest v0 release)
#   SITE_URL   (default https://fpsot.org)
#   PDF_DIR    folder holding the release PDFs, <repo>-en.pdf and <repo>-fr.pdf: each
#              is published next to its language's pages and linked from each page.
#              One missing for a language the spec has fails.
set -euo pipefail
repo_dir=$(cd "${1:?usage: site-bundle.sh REPO_DIR CONTENT_DIR [PUBLIC_DIR]}" && pwd)
content=${2:?usage: site-bundle.sh REPO_DIR CONTENT_DIR [PUBLIC_DIR]}
mkdir -p "$content"
content=$(cd "$content" && pwd)
public=${3:-$content/../public}
: "${TOOLS_BIN:?TOOLS_BIN must point to the built tools}"
here=$(cd "$(dirname "$0")" && pwd)

remote=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
name=$(basename "${remote:-$repo_dir}" .git)
if ! tag=$(git -C "$repo_dir" describe --tags --exact-match --match 'v*.*.*' 2>/dev/null); then
  echo "error: $name is not at a release tag (vX.Y.Z)" >&2
  exit 1
fi
spec=${name#fpsot-spec-}
version=${tag#v}
case "$remote" in
  git@github.com:*) repo_url="https://github.com/${remote#git@github.com:}" ;;
  "") repo_url="https://github.com/fpsot-org/$name" ;;
  *) repo_url=$remote ;;
esac
repo_url=${repo_url%.git}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "${TERMBASE:-}" ]; then
  TERMBASE=$(cd "$(dirname "$TERMBASE")" && pwd)/$(basename "$TERMBASE")
elif [ -f "$repo_dir/termbase/terms.yaml" ]; then
  TERMBASE="$repo_dir/termbase/terms.yaml"
else
  TERMBASE="$work/terms.yaml"
  bash "$here/fetch-spec-file.sh" https://github.com/fpsot-org/fpsot-spec-writing.git "" termbase/terms.yaml "$TERMBASE" >&2
fi

echo "site-bundle: $name $tag" >&2
(cd "$repo_dir" && TOOLS_BIN="$TOOLS_BIN" TERMBASE="$TERMBASE" STRICT=false DOC_RULES=false LINKML="" \
  bash "$here/spec-generate.sh") >&2 || { echo "error: $name: generating the pages failed" >&2; exit 1; }

git -C "$repo_dir" ls-files -- 'spec/*.adoc' 'docs/*.adoc' | while read -r f; do
  printf '%s\t%s\n' "$f" "$(git -C "$repo_dir" log -1 --format=%cs -- "$f")"
done > "$work/dates.tsv"
tag_date=$(git -C "$repo_dir" log -1 --format=%cs "$tag")

pdfs=()
if [ -n "${PDF_DIR:-}" ]; then
  for l in en fr; do
    [ -d "$repo_dir/spec/$l" ] || continue
    pdf="$PDF_DIR/$name-$l.pdf"
    [ -s "$pdf" ] || { echo "error: $name $tag: no PDF $name-$l.pdf in $PDF_DIR" >&2; exit 1; }
    pdfs+=(-pdf-"$l" "$(cd "$PDF_DIR" && pwd)/$name-$l.pdf")
  done
fi

"$TOOLS_BIN/sitecollect" -spec "$spec" -src "$repo_dir" -out "$content" -public "$public" \
  -version "$version" -dates "$work/dates.tsv" -default-date "$tag_date" \
  -repo-url "$repo_url" -site-url "${SITE_URL:-https://fpsot.org}" "${pdfs[@]}" || { echo "error: $name: sitecollect failed" >&2; exit 1; }
