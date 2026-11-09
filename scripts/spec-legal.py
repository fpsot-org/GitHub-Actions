#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Writes the legal notice of an FPSOT spec, as JSON, from the spec repository:
#   - the copyright lines, from NOTICE ("Copyright <years> <holder>");
#   - the spec license, from publiccode.yml (legal.license, an SPDX ID);
#   - the code sample license, from the "Source Code License" section of LICENSE.md
#     (optional: a spec without code samples may leave it out).
# The license is one value per repository. A license this script does not know fails,
# so a new one is named in both languages here before it is used.
#
# Usage:
#   spec-legal.py spec REPO_DIR LANG VERSION DATE SOURCE_URL
#       the notice page of one spec's PDF (DATE: release date, YYYY-MM-DD)
#   spec-legal.py book LANG DATE REPO_DIR VERSION SOURCE_URL [REPO_DIR VERSION SOURCE_URL]...
#       the notice page of the book with several specs (DATE: build date)
#   spec-legal.py site REPO_DIR
#       the license line of the site pages, in each language
# LANG: en or fr. The spec and book notices print {"lang", "paragraphs", "rights",
# "rights_url"}: each paragraph is a list of {"text", "href"?} runs, for odt-to-pdf.py;
# "rights" is the statement for the PDF metadata (XMP dc:rights) and "rights_url"
# the license URL (xmpRights:WebStatement).
import json
import os
import re
import sys

# Names of each license, in a sentence, and its URL.
LICENSES = {
    "Community-Spec-1.0": {
        "en": "Community Specification License 1.0", "fr": "licence Community Specification 1.0",
        "url": {"en": "https://github.com/CommunitySpecification/1.0", "fr": "https://github.com/CommunitySpecification/1.0"}},
    "CC-BY-4.0": {
        "en": "Creative Commons Attribution 4.0 International License",
        "fr": "licence Creative Commons Attribution 4.0 International",
        "url": {"en": "https://creativecommons.org/licenses/by/4.0/", "fr": "https://creativecommons.org/licenses/by/4.0/deed.fr"}},
    "Apache-2.0": {
        "en": "Apache License 2.0", "fr": "licence Apache 2.0",
        "url": {"en": "https://www.apache.org/licenses/LICENSE-2.0", "fr": "https://www.apache.org/licenses/LICENSE-2.0"}},
    "MIT": {
        "en": "MIT License", "fr": "licence MIT",
        "url": {"en": "https://opensource.org/licenses/MIT", "fr": "https://opensource.org/licenses/MIT"}},
}
# How LICENSE.md names a code license: the URL it links, or its name.
CODE_LICENSE_SIGNS = [
    ("Apache-2.0", r"apache\.org/licenses/LICENSE-2\.0|Apache License,? (Version )?2\.0"),
    ("MIT", r"opensource\.org/licenses/MIT|\bMIT License\b"),
]
# Copyright holders, as NOTICE names them, in French. Others stay as they are.
HOLDERS_FR = {"The FPSOT Authors": "Les auteurs de la FPSOT"}
NBSP = " "


def fail(msg):
    sys.exit("spec-legal.py: " + msg)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        fail("%s: %s" % (path, e.strerror))


def copyrights(repo):
    """Returns [(years, holder)] from NOTICE, years as a set of ints."""
    path = os.path.join(repo, "NOTICE")
    out = []
    for line in read(path).splitlines():
        m = re.match(r"^\s*Copyright\s+(?:©\s*|\(c\)\s*)?(\d{4}(?:\s*[-–,]\s*\d{4})*)\s+(.+?)\s*$", line)
        if m:
            years = set()
            for part in re.split(r"\s*,\s*", m.group(1)):
                bounds = re.split(r"\s*[-–]\s*", part)
                years.update(range(int(bounds[0]), int(bounds[-1]) + 1))
            out.append((years, m.group(2)))
    if not out:
        fail("%s has no \"Copyright <years> <holder>\" line" % path)
    return out


def license_id(repo):
    path = os.path.join(repo, "publiccode.yml")
    m = re.search(r"^legal:[ \t]*\n(?:[ \t]+.*\n)*?[ \t]+license:\s*[\"']?([^\"'\s#]+)", read(path) + "\n", re.M)
    if not m:
        fail("%s has no legal.license" % path)
    if m.group(1) not in LICENSES:
        fail("%s: legal.license %s is not one of %s" % (path, m.group(1), ", ".join(sorted(LICENSES))))
    return m.group(1)


def code_license_id(repo):
    path = os.path.join(repo, "LICENSE.md")
    text = read(path)
    m = re.search(r"^##\s+Source Code License\s*$(.*?)(?=^##\s|\Z)", text, re.M | re.S)
    if not m:
        return None
    for spdx, sign in CODE_LICENSE_SIGNS:
        if re.search(sign, m.group(1)):
            return spdx
    fail("%s: the Source Code License section names no license of %s" % (path, ", ".join(s for s, _ in CODE_LICENSE_SIGNS)))


def year_text(years):
    years = sorted(years)
    if years == list(range(years[0], years[-1] + 1)):
        return str(years[0]) if len(years) == 1 else "%d-%d" % (years[0], years[-1])
    return ", ".join(str(y) for y in years)


def copyright_lines(pairs, lang):
    """Merges the years of each holder, in the order holders first appear."""
    holders = {}
    for years, holder in pairs:
        holders.setdefault(holder, set()).update(years)
    if lang == "fr":
        return ["© %s %s" % (year_text(y), HOLDERS_FR.get(h, h)) for h, y in holders.items()]
    return ["Copyright %s %s" % (year_text(y), h) for h, y in holders.items()]


def book_title(repo, lang):
    path = os.path.join(repo, "spec", lang, "book.adoc")
    first = read(path).lstrip("﻿").split("\n", 1)[0]
    if not first.startswith("= "):
        fail("%s: the first line must be the book title (\"= ...\")" % path)
    title = first[2:].strip()
    # Asciidoctor makes an apostrophe between letters typographic: so does the notice.
    return re.sub(r"(?<=\w)'(?=\w)", "’", title)


def link(spdx, lang):
    return {"text": LICENSES[spdx][lang], "href": LICENSES[spdx]["url"][lang]}


def colon(lang):
    return NBSP + ": " if lang == "fr" else ": "


class Repo:
    def __init__(self, path, lang):
        self.path, self.lang = path, lang
        self.copyrights = copyrights(path)
        self.license = license_id(path)
        self.code = code_license_id(path)
        self.title = book_title(path, lang)


def spec_notice(repo, lang, version, date, source):
    r = Repo(repo, lang)
    fr = lang == "fr"
    paras = [[{"text": r.title}],
             [{"text": ("Version %s, publiée le %s" if fr else "Version %s, released %s") % (version, date)}]]
    paras += [[{"text": c}] for c in copyright_lines(r.copyrights, lang)]
    paras.append([{"text": "Cette spécification est publiée sous la " if fr else "This specification is licensed under the "},
                  link(r.license, lang), {"text": "."}])
    if r.code:
        paras.append([{"text": "Les exemples de code qu’elle contient sont publiés sous la " if fr else "Code samples in it are licensed under the "},
                      link(r.code, lang), {"text": ", sauf mention contraire." if fr else ", unless marked otherwise."}])
    paras.append([{"text": "Source" + colon(lang)}, {"text": source, "href": source}])
    return {"lang": lang, "paragraphs": paras, "rights": rights(paras[2:-1]),
            "rights_url": LICENSES[r.license]["url"][lang]}


def book_notice(lang, date, parts):
    fr = lang == "fr"
    repos = [(Repo(path, lang), version, source) for path, version, source in parts]
    paras = [[{"text": "Spécifications FPSOT" if fr else "FPSOT specifications"}],
             [{"text": ("Produit le %s à partir de la dernière version publiée de chaque spécification" if fr
                        else "Built on %s from the latest release of each specification") % date}]]
    paras += [[{"text": c}] for c in copyright_lines([c for r, _, _ in repos for c in r.copyrights], lang)]
    first = len(paras)
    if len({(r.license, r.code) for r, _, _ in repos}) == 1:
        r = repos[0][0]
        paras.append([{"text": "Chaque partie de ce livre est publiée sous la " if fr else "Each part of this book is licensed under the "},
                      link(r.license, lang), {"text": "."}])
        if r.code:
            paras.append([{"text": "Les exemples de code qu’il contient sont publiés sous la " if fr else "Code samples in it are licensed under the "},
                          link(r.code, lang), {"text": ", sauf mention contraire." if fr else ", unless marked otherwise."}])
        last = len(paras)
        paras.append([{"text": "Sources" + colon(lang).rstrip()}])
        for r, version, source in repos:
            paras.append([{"text": "%s %s%s" % (r.title, version, colon(lang))}, {"text": source, "href": source}])
        rights_url = LICENSES[r.license]["url"][lang]
    else:
        paras.append([{"text": "Chaque partie de ce livre est publiée sous la licence de sa spécification :" if fr
                       else "Each part of this book is licensed as its own specification:"}])
        for r, version, source in repos:
            run = [{"text": "%s %s%s" % (r.title, version, colon(lang))}, link(r.license, lang)]
            if r.code:
                run += [{"text": " ; exemples de code : " if fr else "; code samples: "}, link(r.code, lang),
                        {"text": ", sauf mention contraire." if fr else ", unless marked otherwise."}]
            else:
                run.append({"text": "."})
            paras.append(run)
            # A source URL on a line of its own wraps less.
            paras.append([{"text": "Source" + colon(lang)}, {"text": source, "href": source}])
        last = len(paras)
        rights_url = ""
        # The rights statement names the licenses, not the sources.
        paras_rights = [p for p in paras[2:last] if not p[0]["text"].startswith("Source")]
        return {"lang": lang, "paragraphs": paras, "rights": rights(paras_rights), "rights_url": rights_url}
    return {"lang": lang, "paragraphs": paras, "rights": rights(paras[2:last]), "rights_url": rights_url}


def rights(paras):
    """The notice as one statement, for the PDF metadata."""
    out = []
    for p in paras:
        s = "".join(run["text"] for run in p).strip()
        out.append(s if s.endswith((".", ":")) else s + ".")
    return " ".join(out).replace(NBSP, " ")


def site(repo):
    out = {}
    for lang in ("en", "fr"):
        r = Repo(repo, lang)
        out[lang] = {"copyright": " · ".join(copyright_lines(r.copyrights, lang)),
                     "license": LICENSES[r.license][lang], "license-url": LICENSES[r.license]["url"][lang],
                     "code": LICENSES[r.code][lang] if r.code else "", "code-url": LICENSES[r.code]["url"][lang] if r.code else ""}
    return out


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "spec" and len(argv) == 7:
        if argv[3] not in ("en", "fr"):
            fail("LANG must be en or fr")
        out = spec_notice(argv[2], argv[3], argv[4], argv[5], argv[6])
    elif cmd == "book" and len(argv) >= 7 and (len(argv) - 4) % 3 == 0:
        if argv[2] not in ("en", "fr"):
            fail("LANG must be en or fr")
        out = book_notice(argv[2], argv[3], [tuple(argv[i:i + 3]) for i in range(4, len(argv), 3)])
    elif cmd == "site" and len(argv) == 3:
        out = site(argv[2])
    else:
        sys.exit("usage: spec-legal.py spec REPO_DIR LANG VERSION DATE SOURCE_URL\n"
                 "       spec-legal.py book LANG DATE REPO_DIR VERSION SOURCE_URL [REPO_DIR VERSION SOURCE_URL]...\n"
                 "       spec-legal.py site REPO_DIR")
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
    print()


if __name__ == "__main__":
    main(sys.argv)
