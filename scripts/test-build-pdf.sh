#!/usr/bin/env bash
# Tests for build-pdf.sh: each test book becomes a tagged PDF/UA-1 and PDF/A-2b file
# with its title and language set, and French accents survive. With PDF_NOTICE, the
# legal notice is a page of its own after the title page, before the contents, and
# its rights statement and license URL are in the XMP metadata.
# Needs asciidoctor, pandoc, LibreOffice (soffice), poppler-utils and qpdf.
# With VERAPDF_IMAGE set (the veraPDF CLI image), each PDF must also pass veraPDF's
# PDF/UA-1 and PDF/A-2b checks. CONTAINER selects docker (default) or podman.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
check_pdf() { # lang-dir lang-tag title
  pdf="$work/$1.pdf"
  if ! PDF_NOTICE="$work/notice-$1.json" bash "$here/build-pdf.sh" "$here/testdata/book/$1/book.adoc" "$pdf" "$2" >"$work/$1.log" 2>&1; then
    echo "FAIL: $1: build-pdf.sh failed:"; cat "$work/$1.log"; fail=1; return
  fi
  info="$(pdfinfo "$pdf")"
  grep -q '^Tagged: *yes' <<<"$info" || { echo "FAIL: $1: PDF is not tagged"; fail=1; }
  grep -qxF "Title: $3" <<<"$(sed 's/^Title: */Title: /' <<<"$info")" || { echo "FAIL: $1: title is not '$3'"; grep '^Title' <<<"$info"; fail=1; }
  meta="$(pdfinfo -meta "$pdf")"
  grep -q 'pdfuaid:part' <<<"$meta" || { echo "FAIL: $1: no PDF/UA identifier"; fail=1; }
  grep -q 'pdfaid:part' <<<"$meta" || { echo "FAIL: $1: no PDF/A identifier"; fail=1; }
  qpdf --qdf --object-streams=disable "$pdf" "$work/$1.qdf.pdf"
  if [ -n "${VERAPDF_IMAGE:-}" ]; then
    # The veraPDF image runs as a user that is not the owner of the work folder.
    chmod a+rx "$work" && chmod a+r "$pdf"
    for flavour in ua1 2b; do
      result=$(${CONTAINER:-docker} run --rm -v "$work:/data:Z" "$VERAPDF_IMAGE" --format text --flavour "$flavour" "/data/$1.pdf" 2>&1 | tail -1)
      if [[ "$result" != PASS* ]]; then
        echo "FAIL: $1: veraPDF $flavour: $result"; fail=1
        # The rules that failed, from the machine-readable report.
        ${CONTAINER:-docker} run --rm -v "$work:/data:Z" "$VERAPDF_IMAGE" --format mrr --flavour "$flavour" "/data/$1.pdf" 2>/dev/null \
          | grep -o 'clause="[^"]*" testNumber="[^"]*" status="failed"[^>]*' | sed 's/^/  /'
      fi
    done
  fi
  grep -aq "/Lang ($2)" "$work/$1.qdf.pdf" || { echo "FAIL: $1: /Lang ($2) not set"; grep -ao '/Lang ([^)]*)' "$work/$1.qdf.pdf" | head -1; fail=1; }
}
# The notices, as spec-legal.py writes them for spec-good.
for l in en fr; do
  python3 -I "$here/spec-legal.py" spec "$here/../testdata/spec-good" "$l" 0.1.0 2026-11-05 \
    https://github.com/fpsot-org/fpsot-spec-good/tree/v0.1.0 > "$work/notice-$l.json" || exit 1
done
check_pdf en en-US "FPSOT test specification"
# Asciidoctor turns the apostrophe into a typographic one (U+2019).
check_pdf fr fr-CA "Spécification d’essai FPSOT"
# The notice is page 2, alone: the title is on page 1, the contents start on page 3.
for l in en fr; do
  [ -f "$work/$l.pdf" ] || continue
  heading="Contents"; [ "$l" = fr ] && heading="Table des matières"
  p1=$(pdftotext -f 1 -l 1 "$work/$l.pdf" -) p2=$(pdftotext -f 2 -l 2 "$work/$l.pdf" -) p3=$(pdftotext -f 3 -l 3 "$work/$l.pdf" -)
  copyright="Copyright 2026 The FPSOT Authors"; [ "$l" = fr ] && copyright="© 2026 Les auteurs de la FPSOT"
  grep -qF "$copyright" <<<"$p2" || { echo "FAIL: $l: page 2 is not the notice:"; head -5 <<<"$p2"; fail=1; }
  grep -qF "$copyright" <<<"$p1$p3" && { echo "FAIL: $l: the notice is not alone on its page"; fail=1; }
  grep -q "^$heading" <<<"$p3" || { echo "FAIL: $l: the contents do not start on page 3"; fail=1; }
  grep -q "^$heading" <<<"$p1$p2" && { echo "FAIL: $l: the contents start before page 3"; fail=1; }
  grep -aqF '/URI (https://github.com/CommunitySpecification/1.0)' "$work/$l.qdf.pdf" || { echo "FAIL: $l: the license is not a link"; fail=1; }
  meta="$(pdfinfo -meta "$work/$l.pdf")"
  grep -qF "$copyright." <<<"$meta" && grep -q '<dc:rights' <<<"$meta" || { echo "FAIL: $l: no dc:rights with the copyright"; fail=1; }
  grep -qF 'https://github.com/CommunitySpecification/1.0' <<<"$(grep -A2 'WebStatement' <<<"$meta")" || { echo "FAIL: $l: no xmpRights:WebStatement"; fail=1; }
done
# The table of contents is filled in: its heading and a chapter title come before the chapter text.
if [ -f "$work/en.pdf" ]; then
  pdftotext "$work/en.pdf" - | awk '/This chapter holds one rule/{exit} /^Rules/{n++} END{exit !(n>=2)}' \
    || { echo "FAIL: en: table of contents is empty"; fail=1; }
fi
# A table row never breaks across two pages: each row's first and last words are on the same page.
if [ -f "$work/en.pdf" ]; then
  pages=$(pdfinfo "$work/en.pdf" | awk '/^Pages:/{print $2}')
  for p in $(seq 1 "$pages"); do pdftotext -f "$p" -l "$p" "$work/en.pdf" - | grep -o 'row[0-9][0-9]\(start\|end\)' | sed "s/^/$p /"; done > "$work/rows.txt"
  split=$(awk '{r=substr($2,4,2); if ($2 ~ /start/) s[r]=$1; else if (s[r] != $1) print "row" r}' "$work/rows.txt")
  [ "$(grep -c start "$work/rows.txt")" = 60 ] || { echo "FAIL: en: expected 60 table rows, found $(grep -c start "$work/rows.txt")"; fail=1; }
  [ -z "$split" ] || { echo "FAIL: en: table rows break across pages:" $split; fail=1; }
fi
# A paragraph that holds a link never breaks across two pages: each link's first and last words are on the same page.
if [ -f "$work/en.pdf" ]; then
  pages=$(pdfinfo "$work/en.pdf" | awk '/^Pages:/{print $2}')
  for p in $(seq 1 "$pages"); do pdftotext -f "$p" -l "$p" "$work/en.pdf" - | grep -o 'link[0-9][0-9]\(start\|end\)' | sed "s/^/$p /"; done > "$work/links.txt"
  split=$(awk '{r=substr($2,5,2); if ($2 ~ /start/) s[r]=$1; else if (s[r] != $1) print "link" r}' "$work/links.txt")
  [ "$(grep -c start "$work/links.txt")" = 80 ] || { echo "FAIL: en: expected 80 links, found $(grep -c start "$work/links.txt")"; fail=1; }
  [ -z "$split" ] || { echo "FAIL: en: links break across pages:" $split; fail=1; }
fi
if [ -f "$work/fr.pdf" ]; then
  pdftotext "$work/fr.pdf" - | grep -q 'Spécification, élément, ça, où, déjà' || { echo "FAIL: fr: accents lost in text"; fail=1; }
fi
# A text alternative per image: when the counts differ, odt-to-pdf.py fails rather
# than give an image the alternative of another one.
asciidoctor -b docbook5 -d book -o "$work/count.xml" "$here/testdata/book/en/book.adoc"
pandoc -f docbook -t odt --resource-path="$here/testdata/book/en" -o "$work/count.odt" "$work/count.xml"
echo '["one", "two"]' > "$work/count-alts.json"
if python3 "$here/odt-to-pdf.py" "$work/count.odt" "$work/count.pdf" "$work/count-profile" "$work/count-alts.json" >"$work/count.log" 2>&1; then
  echo "FAIL: odt-to-pdf.py accepted 2 text alternatives for 1 image"; fail=1
fi
grep -q '2 text alternatives for 1 image' "$work/count.log" || { echo "FAIL: count message missing:"; cat "$work/count.log"; fail=1; }
[ $fail -eq 0 ] && echo "PASS"
exit $fail
