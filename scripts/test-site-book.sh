#!/usr/bin/env bash
# Tests "site-build.sh book": two specs whose requirement IDs, page names and glossary
# anchors are the same (spec-good and spec-book) become one tagged PDF per language,
# with each spec as a part, in the order given, and its version. Asciidoctor runs
# with --failure-level WARN, so the book builds only when no ID collides. A link
# that leads nowhere in the book fails the build.
# Needs Go, git, asciidoctor, pandoc, LibreOffice (soffice), poppler-utils and qpdf.
# With VERAPDF_IMAGE set (the veraPDF CLI image), each PDF must also pass veraPDF's
# PDF/UA-1 and PDF/A-2b checks. CONTAINER selects docker (default) or podman.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"
fail=0
if [ ! -x "${TOOLS_BIN:-}/termgen" ]; then
  (cd "$repo/tools" && go build -buildvcs=false -o "$work/bin/" ./cmd/...) || exit 1
  TOOLS_BIN="$work/bin"
fi
export TOOLS_BIN TERMBASE="$repo/testdata/terms.yaml" SPEC_SOURCE_DIR="$work/repos"
git_t() { git -c user.name=t -c user.email=t@example.org -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
fixture() { # testdata-dir repo-name
  cp -r "$repo/testdata/$1" "$work/repos/$2"
  git_t -C "$work/repos/$2" init -q
  git_t -C "$work/repos/$2" add -A
  git_t -C "$work/repos/$2" commit -q -m fixture
  git_t -C "$work/repos/$2" tag -a v0.1.0 -m v0.1.0
}
mkdir -p "$work/repos"
fixture spec-good fpsot-spec-good
fixture spec-book fpsot-spec-book
git_t -C "$work/repos/fpsot-spec-book" commit -q --allow-empty -m next
git_t -C "$work/repos/fpsot-spec-book" tag -a v0.2.0 -m v0.2.0

if ! bash "$here/site-build.sh" book "$work/out" fpsot-spec-good v0.1.0 fpsot-spec-book v0.2.0 >"$work/book.log" 2>&1; then
  echo "FAIL: book:"; tail -40 "$work/book.log"; fail=1
fi
check_pdf() { # file lang-tag title
  local pdf="$work/out/$1"
  [ -s "$pdf" ] || { echo "FAIL: $1 not written"; fail=1; return; }
  local info
  info="$(pdfinfo "$pdf")"
  grep -q '^Tagged: *yes' <<<"$info" || { echo "FAIL: $1 is not tagged"; fail=1; }
  grep -qx "Title: *$3" <<<"$info" || { echo "FAIL: $1: title is not '$3'"; grep '^Title' <<<"$info"; fail=1; }
  pdfinfo -meta "$pdf" | grep -q 'pdfuaid:part' || { echo "FAIL: $1: no PDF/UA identifier"; fail=1; }
  qpdf --qdf --object-streams=disable "$pdf" "$work/$1.qdf"
  grep -aq "/Lang ($2)" "$work/$1.qdf" || { echo "FAIL: $1: /Lang ($2) not set"; fail=1; }
  if [ -n "${VERAPDF_IMAGE:-}" ]; then
    chmod a+rx "$work" "$work/out" && chmod a+r "$pdf"
    for flavour in ua1 2b; do
      result=$(${CONTAINER:-docker} run --rm -v "$work/out:/data:Z" "$VERAPDF_IMAGE" --format text --flavour "$flavour" "/data/$1" 2>&1 | tail -1)
      if [[ "$result" != PASS* ]]; then
        echo "FAIL: $1: veraPDF $flavour: $result"; fail=1
        ${CONTAINER:-docker} run --rm -v "$work/out:/data:Z" "$VERAPDF_IMAGE" --format mrr --flavour "$flavour" "/data/$1" 2>/dev/null \
          | grep -o 'clause="[^"]*" testNumber="[^"]*" status="failed"[^>]*' | sed 's/^/  /'
      fi
    done
  fi
}
check_pdf fpsot-specifications-en.pdf en-US "FPSOT specifications"
check_pdf fpsot-specifications-fr.pdf fr-CA "Spécifications FPSOT"
if [ -s "$work/out/fpsot-specifications-en.pdf" ]; then
  text=$(pdftotext "$work/out/fpsot-specifications-en.pdf" -)
  # Each spec is a part, in the order given, with its version; the text of each is there.
  order=$(grep -nxE 'Test spec book|Book test specification|Version 0\.[12]\.0' <<<"$text" | cut -d: -f2 | uniq | tr '\n' '|')
  [[ "$order" == *"Test spec book|Version 0.1.0|"*"Book test specification|Version 0.2.0|"* ]] \
    || { echo "FAIL: en: parts not in order, each with its version: $order"; fail=1; }
  # Page 2 is the legal notice: each part's license and sources, every holder.
  notice=$(pdftotext -f 2 -l 2 "$work/out/fpsot-specifications-en.pdf" -)
  for want in "Copyright 2025-2026 The FPSOT Authors" "Copyright 2026 Example Contributor" \
      "Each part of this book is licensed as its own specification:" "Creative Commons Attribution 4.0"; do
    grep -qF "$want" <<<"$(tr '\n' ' ' <<<"$notice" | sed 's/  */ /g')" || { echo "FAIL: en: the notice lacks: $want"; fail=1; }
  done
  grep -aqF '/URI (https://github.com/fpsot-org/fpsot-spec-book/tree/v0.2.0)' "$work/fpsot-specifications-en.pdf.qdf" \
    || { echo "FAIL: en: the notice does not link the second part's sources"; fail=1; }
  pdfinfo -meta "$work/out/fpsot-specifications-en.pdf" | grep -q '<dc:rights' || { echo "FAIL: en: no dc:rights"; fail=1; }
  grep -q 'A test page MUST exist' <<<"$text" || { echo "FAIL: en: the first spec's text is missing"; fail=1; }
  grep -q 'MUST point back to' <<<"$text" || { echo "FAIL: en: the second spec's text is missing"; fail=1; }
  # A listing block keeps its anchors and links as written.
  grep -qF '[[TST-001]]' <<<"$text" && grep -qF 'xref:glossary.adoc#gl-api[API]' <<<"$text" \
    || { echo "FAIL: en: the listing block was rewritten"; fail=1; }
  # A link to a guide, which the book does not hold, goes to the guide on the site.
  grep -aqF '/URI (https://fpsot.org/book/guides/how-to/)' "$work/fpsot-specifications-en.pdf.qdf" \
    || { echo "FAIL: en: the guide link does not go to the site"; fail=1; }
fi
if [ -s "$work/out/fpsot-specifications-fr.pdf" ]; then
  pdftotext -f 2 -l 2 "$work/out/fpsot-specifications-fr.pdf" - | grep -qF '© 2025-2026 Les auteurs de la FPSOT' \
    || { echo "FAIL: fr: the notice lacks the copyright"; fail=1; }
  pdftotext "$work/out/fpsot-specifications-fr.pdf" - | grep -q 'Chaque appel' || { echo "FAIL: fr: the second spec's text is missing"; fail=1; }
  grep -aqF '/URI (https://fpsot.org/fr/book/guides/how-to/)' "$work/fpsot-specifications-fr.pdf.qdf" \
    || { echo "FAIL: fr: the guide link does not go to the site"; fail=1; }
fi

# A link to a page that is not in the book fails, and names the page.
fixture spec-book fpsot-spec-broken
printf '\nSee xref:missing.adoc[a page that is not in the book].\n' >> "$work/repos/fpsot-spec-broken/spec/en/rules.adoc"
git_t -C "$work/repos/fpsot-spec-broken" commit -q -am broken
git_t -C "$work/repos/fpsot-spec-broken" tag -a v0.1.1 -m v0.1.1
if bash "$here/site-build.sh" book "$work/out-broken" fpsot-spec-broken v0.1.1 >"$work/broken.log" 2>&1; then
  echo "FAIL: book accepted a link to a page that is not in the book"; fail=1
fi
grep -q 'missing' "$work/broken.log" || { echo "FAIL: broken link not named:"; tail -10 "$work/broken.log"; fail=1; }
# A tag that does not exist fails, and names it.
if bash "$here/site-build.sh" book "$work/out-v9" fpsot-spec-good v9.9.9 >"$work/v9.log" 2>&1; then
  echo "FAIL: book accepted a tag that does not exist"; fail=1
fi
grep -q 'v9.9.9' "$work/v9.log" || { echo "FAIL: missing tag not named:"; cat "$work/v9.log"; fail=1; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
