#!/usr/bin/env bash
# Tests release-pdfs.sh with a fake gh: it replaces the PDF assets of an existing
# release, and adds one note to its release notes, in English and French, however
# often it runs. A release that does not exist, or a folder without the PDFs of both
# languages, fails before anything changes.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
mkdir -p "$work/bin" "$work/pdf"
# The fake keeps the release notes in $work/body and logs each call in $work/calls.
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_WORK/calls"
case "$1 $2" in
  "release view")
    [ "$3" = v0.1.0 ] || { echo "release not found" >&2; exit 1; }
    cat "$GH_WORK/body" ;;
  "release upload") ;;
  "release edit")
    while [ $# -gt 0 ]; do [ "$1" = --notes-file ] && cp "$2" "$GH_WORK/body"; shift; done ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GH_WORK="$work" GH_TOKEN=t
printf 'See CHANGELOG.md for what changed.' > "$work/body"
printf '%%PDF en' > "$work/pdf/fpsot-spec-x-en.pdf"
printf '%%PDF fr' > "$work/pdf/fpsot-spec-x-fr.pdf"

for run in 1 2; do
  if ! bash "$here/release-pdfs.sh" fpsot-spec-x v0.1.0 "$work/pdf" >"$work/out" 2>&1; then
    echo "FAIL: run $run:"; cat "$work/out"; fail=1
  fi
done
grep -q -- "release upload v0.1.0 --repo fpsot-org/fpsot-spec-x --clobber $work/pdf/fpsot-spec-x-en.pdf $work/pdf/fpsot-spec-x-fr.pdf" "$work/calls" \
  || { echo "FAIL: PDFs not uploaded with --clobber:"; cat "$work/calls"; fail=1; }
body=$(cat "$work/body")
grep -q '^See CHANGELOG.md for what changed.' <<<"$body" || { echo "FAIL: the notes lost their text:"; echo "$body"; fail=1; }
[ "$(grep -c 'The PDF books were rebuilt on' <<<"$body")" = 1 ] || { echo "FAIL: want one English note:"; echo "$body"; fail=1; }
[ "$(grep -c 'Les livres PDF ont été reconstruits le' <<<"$body")" = 1 ] || { echo "FAIL: want one French note:"; echo "$body"; fail=1; }

: > "$work/calls"
bash "$here/release-pdfs.sh" fpsot-spec-x v9.9.9 "$work/pdf" >"$work/out" 2>&1 && { echo "FAIL: accepted a release that does not exist"; fail=1; }
grep -q 'v9.9.9' "$work/out" || { echo "FAIL: missing release not named:"; cat "$work/out"; fail=1; }
rm "$work/pdf/fpsot-spec-x-fr.pdf"
bash "$here/release-pdfs.sh" fpsot-spec-x v0.1.0 "$work/pdf" >"$work/out" 2>&1 && { echo "FAIL: accepted a folder without the French PDF"; fail=1; }
grep -q 'fpsot-spec-x-fr.pdf' "$work/out" || { echo "FAIL: missing PDF not named:"; cat "$work/out"; fail=1; }
grep -q 'upload\|edit' "$work/calls" && { echo "FAIL: changed a release after a failed check"; fail=1; }
[ $fail -eq 0 ] && echo "PASS"
exit $fail
