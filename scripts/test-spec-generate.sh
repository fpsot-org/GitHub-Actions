#!/usr/bin/env bash
# Tests spec-generate.sh and spec-render.sh on the spec-good fixture: abbreviations
# render as <abbr>, the glossary and jurisdiction pages exist, each page shows its
# version and date, and doccheck rejects the spec-bad-history fixture.
# Needs Go, asciidoctor and git. LinkML validation is skipped unless LINKML is set.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
(cd "$repo/tools" && go build -o "$work/bin/" ./cmd/...) || exit 1
cp -r "$repo/testdata/spec-good" "$work/spec"
export TOOLS_BIN="$work/bin" TERMBASE="$repo/testdata/terms.yaml" MODEL="$repo/testdata/jurisdiction-model.yaml" DOC_RULES=true STRICT=false
if ! (cd "$work/spec" && bash "$here/spec-generate.sh") >"$work/gen.log" 2>&1; then
  echo "FAIL: spec-generate.sh on spec-good:"; cat "$work/gen.log"; fail=1
fi
for f in spec/en/_fpsot-terms.adoc spec/fr/glossary.adoc docs/modules/en/pages/_fpsot-terms.adoc docs/modules/fr/pages/jurisdictions/pages/ca/index.adoc; do
  [ -f "$work/spec/$f" ] || { echo "FAIL: $f not generated"; fail=1; }
done
export SPEC_VERSION=0.1.0-dev CONTRIBUTING_URL=https://example.org/CONTRIBUTING.md
if ! (cd "$work/spec" && bash "$here/spec-render.sh" "$work/html") >"$work/render.log" 2>&1; then
  echo "FAIL: spec-render.sh:"; cat "$work/render.log"; fail=1
fi
expect() { # file pattern
  grep -qF -- "$2" "$work/html/$1" 2>/dev/null || { echo "FAIL: $1 lacks: $2"; fail=1; }
}
expect spec/en/index.html '<abbr title="application programming interface">API</abbr>'
expect spec/en/index.html 'href="glossary.html#gl-api"'
expect spec/en/index.html 'id="revnumber">version 0.1.0-dev'
# Diagrams are copied next to the pages, so an embedded image resolves.
expect spec/en/index.html 'src="../../diagrams/hello.svg"'
[ -f "$work/html/diagrams/hello.svg" ] || { echo "FAIL: diagrams/hello.svg not copied"; fail=1; }
expect spec/en/index.html 'id="revdate">'
expect spec/en/book.html 'href="#gl-api"'
expect spec/en/book.html 'id="gl-api"'
expect docs/modules/fr/pages/index.html 'href="../../../../spec/fr/glossary.html#gl-api"'
expect docs/modules/en/pages/jurisdictions/pages/fr/index.html 'https://example.org/CONTRIBUTING.md'
# Each page declares its language, and French pages use French labels.
expect spec/en/index.html '<html lang="en"'
expect spec/fr/index.html '<html lang="fr"'
expect spec/fr/glossary.html '<html lang="fr"'
expect docs/modules/fr/pages/jurisdictions/pages/ca/index.html '<html lang="fr"'
expect docs/modules/en/pages/jurisdictions/pages/fr/index.html '<html lang="en"'
expect spec/fr/book.html 'Table des matières'
# The footer would show the checkout time as "Last updated"; pages show their Git date instead.
for f in spec/en/index.html spec/fr/index.html; do
  ! grep -q 'last-update\|Last updated\|Dernière mise à jour' "$work/html/$f" || { echo "FAIL: $f shows a footer update time"; fail=1; }
done
cp -r "$repo/testdata/spec-bad-history" "$work/bad"
if (cd "$work/bad" && bash "$here/spec-generate.sh") >"$work/bad.log" 2>&1; then
  echo "FAIL: spec-bad-history should fail"; fail=1
fi
grep -q 'must end with "== Document history"' "$work/bad.log" || { echo "FAIL: bad-history message missing:"; cat "$work/bad.log"; fail=1; }
[ $fail -eq 0 ] && echo "PASS"
exit $fail
