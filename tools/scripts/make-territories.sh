#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds internal/jurisdiction/territories.json from Unicode CLDR data:
# the five UN M49 continents, the ISO 3166-1 countries each contains, and their
# names in English and Canadian French.
#
# Usage: scripts/make-territories.sh CLDR_TAG   (for example 49.0.0)
# CLDR data is under the Unicode License v3; see NOTICE.
set -euo pipefail
tag=${1:?usage: make-territories.sh CLDR_TAG}
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base="https://raw.githubusercontent.com/unicode-org/cldr-json/$tag/cldr-json"
curl -sfLo "$work/tc.json" "$base/cldr-core/supplemental/territoryContainment.json"
curl -sfLo "$work/en.json" "$base/cldr-localenames-full/main/en/territories.json"
curl -sfLo "$work/fr.json" "$base/cldr-localenames-full/main/fr-CA/territories.json"
python3 -I - "$work" "$tag" > "$here/internal/jurisdiction/territories.json" <<'PY'
import json, sys
work, tag = sys.argv[1], sys.argv[2]
tc = json.load(open(f"{work}/tc.json"))["supplemental"]["territoryContainment"]
names = {
    "en": json.load(open(f"{work}/en.json"))["main"]["en"]["localeDisplayNames"]["territories"],
    "fr": json.load(open(f"{work}/fr.json"))["main"]["fr-CA"]["localeDisplayNames"]["territories"],
}
# Codes CLDR places in regions that are not ISO 3166-1 countries
# (exceptionally reserved or user-assigned), and Outlying Oceania.
skip = {"QO", "AC", "CP", "DG", "EA", "IC", "TA", "XK"}

def leaves(code):
    if code in skip:
        return []
    entry = tc.get(code)
    if entry is None or entry.get("_grouping"):
        return [code] if code.isalpha() else []
    out = []
    for child in entry["_contains"]:
        out += leaves(child)
    return out

continents, all_codes = [], set()
for code in ["002", "019", "142", "150", "009"]:
    countries = sorted(set(leaves(code)))
    all_codes |= set(countries)
    continents.append({"code": code, "name": {l: names[l][code] for l in names}, "countries": countries})
out = {
    "source": f"Unicode CLDR {tag}",
    "continents": continents,
    "names": {c: {l: names[l][c] for l in names} for c in sorted(all_codes)},
}
json.dump(out, sys.stdout, ensure_ascii=False, indent=1, sort_keys=False)
print()
PY
echo "wrote internal/jurisdiction/territories.json from CLDR $tag"
