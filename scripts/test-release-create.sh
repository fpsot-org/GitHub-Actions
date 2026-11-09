#!/usr/bin/env bash
# Tests release-create.sh with a fake gh. It attaches the PDF books, and the files of
# an optional extra folder, such as the editable clause modules of the procurement
# spec. An extra folder that is missing or empty, or a file name found in both
# folders, fails before the release is created.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
mkdir -p "$work/bin" "$work/book/en" "$work/book/fr" "$work/extra/en" "$work/empty"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_WORK/calls"
[ "$1 $2" = "release create" ] || { echo "unexpected: $*" >&2; exit 1; }
GH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GH_WORK="$work" GH_TOKEN=t
printf '%%PDF en' > "$work/book/en/fpsot-spec-x-en.pdf"
printf '%%PDF fr' > "$work/book/fr/fpsot-spec-x-fr.pdf"
printf 'odt' > "$work/extra/en/pack-en.odt"
printf 'docx' > "$work/extra/pack-fr.docx"

run() { : > "$work/calls"; bash "$here/release-create.sh" "$@" >"$work/out" 2>&1; }

# 1. PDFs only, as before.
if ! run org/fpsot-spec-x v0.1.0 "$work/book"; then
  echo "FAIL: PDFs only:"; cat "$work/out"; fail=1
fi
want="release create v0.1.0 --repo org/fpsot-spec-x --verify-tag --title v0.1.0 --notes See CHANGELOG.md for what changed. $work/book/en/fpsot-spec-x-en.pdf $work/book/fr/fpsot-spec-x-fr.pdf"
[ "$(cat "$work/calls")" = "$want" ] || { echo "FAIL: PDFs only, got:"; cat "$work/calls"; fail=1; }

# 2. PDFs and the extra files, sorted, from subfolders too.
if ! run org/fpsot-spec-x v0.1.0 "$work/book" "$work/extra"; then
  echo "FAIL: with extras:"; cat "$work/out"; fail=1
fi
want="$want $work/extra/en/pack-en.odt $work/extra/pack-fr.docx"
[ "$(cat "$work/calls")" = "$want" ] || { echo "FAIL: with extras, got:"; cat "$work/calls"; fail=1; }

# 3. An empty or missing extra folder fails, and nothing is created.
for d in "$work/empty" "$work/none"; do
  if run org/fpsot-spec-x v0.1.0 "$work/book" "$d"; then
    echo "FAIL: extra folder $d accepted"; fail=1
  fi
  [ ! -s "$work/calls" ] || { echo "FAIL: release created with extra folder $d"; fail=1; }
done

# 4. Two assets with the same file name fail: GitHub keeps one name per release.
printf 'dup' > "$work/extra/fpsot-spec-x-en.pdf"
if run org/fpsot-spec-x v0.1.0 "$work/book" "$work/extra"; then
  echo "FAIL: duplicate asset name accepted"; fail=1
fi
grep -q "fpsot-spec-x-en.pdf" "$work/out" || { echo "FAIL: duplicate not named:"; cat "$work/out"; fail=1; }
[ ! -s "$work/calls" ] || { echo "FAIL: release created with a duplicate name"; fail=1; }

[ "$fail" = 0 ] && echo "test-release-create: all pass"
exit "$fail"
