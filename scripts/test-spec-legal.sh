#!/usr/bin/env bash
# Tests spec-legal.py: the legal notice of a spec PDF, of the book with several specs,
# and the license line of the site pages, in English and French. The copyright comes
# from NOTICE, the spec license from publiccode.yml (legal.license) and the code
# license from LICENSE.md. A repo without them, or with a license it does not know,
# fails and says why.
# Needs Python 3.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
legal() { python3 -I "$here/spec-legal.py" "$@"; }
# Prints the text of each notice paragraph, one per line, with links as "text<url>",
# and a no-break space as a space (French puts one before a colon).
paras() { python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["paragraphs"]:
    print("".join(s["text"] + ("<%s>" % s["href"] if s.get("href") else "") for s in p).replace("\u00a0", " "))' 2>/dev/null; }
expect() { # name want got
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1:"; diff <(echo "$2") <(echo "$3") | sed 's/^/  /'; fail=1
  fi
}
good="$repo/testdata/spec-good" book="$repo/testdata/spec-book"
src=https://github.com/fpsot-org/fpsot-spec-good/tree/v0.1.0

got=$(legal spec "$good" en 0.1.0 2026-11-05 "$src" | paras)
expect "spec notice (en)" "Test spec book
Version 0.1.0, released 2026-11-05
Copyright 2026 The FPSOT Authors
This specification is licensed under the Community Specification License 1.0<https://github.com/CommunitySpecification/1.0>.
Code samples in it are licensed under the Apache License 2.0<https://www.apache.org/licenses/LICENSE-2.0>, unless marked otherwise.
Source: $src<$src>" "$got"

got=$(legal spec "$good" fr 0.1.0 2026-11-05 "$src" | paras)
expect "spec notice (fr)" "Livre de la spécification d’essai
Version 0.1.0, publiée le 2026-11-05
© 2026 Les auteurs de la FPSOT
Cette spécification est publiée sous la licence Community Specification 1.0<https://github.com/CommunitySpecification/1.0>.
Les exemples de code qu’elle contient sont publiés sous la licence Apache 2.0<https://www.apache.org/licenses/LICENSE-2.0>, sauf mention contraire.
Source : $src<$src>" "$got"

legal spec "$good" fr 0.1.0 2026-11-05 "$src" | grep -q 'Source\\u00a0:\|Source'$'\u00a0'':' || { echo "FAIL: fr: no no-break space before the colon"; fail=1; }
# The PDF metadata: the rights statement and the license URL.
got=$(legal spec "$good" en 0.1.0 2026-11-05 "$src" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["rights"]); print(d["rights_url"])')
expect "spec rights (en)" "Copyright 2026 The FPSOT Authors. This specification is licensed under the Community Specification License 1.0. Code samples in it are licensed under the Apache License 2.0, unless marked otherwise.
https://github.com/CommunitySpecification/1.0" "$got"

# The book: each part's license and sources; holders merged, years joined.
bsrc=https://github.com/fpsot-org/fpsot-spec-book/tree/v0.2.0
got=$(legal book en 2026-11-08 "$good" 0.1.0 "$src" "$book" 0.2.0 "$bsrc" | paras)
expect "book notice (en)" "FPSOT specifications
Built on 2026-11-08 from the latest release of each specification
Copyright 2025-2026 The FPSOT Authors
Copyright 2026 Example Contributor
Each part of this book is licensed as its own specification:
Test spec book 0.1.0: Community Specification License 1.0<https://github.com/CommunitySpecification/1.0>; code samples: Apache License 2.0<https://www.apache.org/licenses/LICENSE-2.0>, unless marked otherwise.
Source: $src<$src>
Book test specification 0.2.0: Creative Commons Attribution 4.0 International License<https://creativecommons.org/licenses/by/4.0/>; code samples: MIT License<https://opensource.org/licenses/MIT>, unless marked otherwise.
Source: $bsrc<$bsrc>" "$got"
got=$(legal book fr 2026-11-08 "$good" 0.1.0 "$src" "$good" 0.1.0 "$src" | paras)
expect "book notice, one license (fr)" "Spécifications FPSOT
Produit le 2026-11-08 à partir de la dernière version publiée de chaque spécification
© 2026 Les auteurs de la FPSOT
Chaque partie de ce livre est publiée sous la licence Community Specification 1.0<https://github.com/CommunitySpecification/1.0>.
Les exemples de code qu’il contient sont publiés sous la licence Apache 2.0<https://www.apache.org/licenses/LICENSE-2.0>, sauf mention contraire.
Sources :
Livre de la spécification d’essai 0.1.0 :
$src<$src>
Livre de la spécification d’essai 0.1.0 :
$src<$src>" "$got"

# The site: one line per language.
got=$(legal site "$good" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); [print(l, *(d[l][k] for k in ("copyright","license","license-url","code","code-url")), sep="|") for l in ("en","fr")]')
expect "site" "en|Copyright 2026 The FPSOT Authors|Community Specification License 1.0|https://github.com/CommunitySpecification/1.0|Apache License 2.0|https://www.apache.org/licenses/LICENSE-2.0
fr|© 2026 Les auteurs de la FPSOT|licence Community Specification 1.0|https://github.com/CommunitySpecification/1.0|licence Apache 2.0|https://www.apache.org/licenses/LICENSE-2.0" "$got"

# Missing or unknown data fails, naming the file.
cp -r "$good" "$work/nocopy" && printf 'Test spec\n' > "$work/nocopy/NOTICE"
legal spec "$work/nocopy" en 0.1.0 2026-11-05 "$src" >/dev/null 2>"$work/err" && { echo "FAIL: accepted a NOTICE without a copyright line"; fail=1; }
grep -q 'NOTICE' "$work/err" || { echo "FAIL: NOTICE not named:"; cat "$work/err"; fail=1; }
cp -r "$good" "$work/unknown" && sed -i 's/Community-Spec-1.0/Nope-1.0/' "$work/unknown/publiccode.yml"
legal spec "$work/unknown" en 0.1.0 2026-11-05 "$src" >/dev/null 2>"$work/err" && { echo "FAIL: accepted an unknown license"; fail=1; }
grep -q 'Nope-1.0' "$work/err" || { echo "FAIL: unknown license not named:"; cat "$work/err"; fail=1; }
cp -r "$good" "$work/nolicense" && printf 'name: x\n' > "$work/nolicense/publiccode.yml"
legal spec "$work/nolicense" en 0.1.0 2026-11-05 "$src" >/dev/null 2>"$work/err" && { echo "FAIL: accepted a publiccode.yml without legal.license"; fail=1; }
grep -q 'publiccode.yml' "$work/err" || { echo "FAIL: publiccode.yml not named:"; cat "$work/err"; fail=1; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
