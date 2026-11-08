#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Writes one AsciiDoc book that holds several FPSOT specs, each as a part, from their
# generated repositories. Each spec's pages keep their own IDs in their own book, so
# two specs often share one: "TST-001", "gl-api" (glossary anchors, and the term
# attributes of _fpsot-terms.adoc that link to them), or a page name. The pages of
# each spec are rewritten in place (run it on throwaway copies) so that every ID the
# spec defines or links to starts with "<spec>_" ("--" would become a dash):
#   [[ID]] [[ID,text]] [#ID] anchor:ID[]          -> <spec>_ID
#   <<ID>> xref:ID[] xref:#ID[] xref:page.adoc#ID[] -> <spec>_ID
#   xref:page.adoc[] <<page.adoc#>>               -> <spec>_page-<page>, an ID that
#                                                    the page's title gets
# A link to a guide (docs/modules/<lang>/pages/) goes to that guide on the site. Any
# other link to a file stays as it is, and the book check fails on it. Listing,
# literal, passthrough and comment blocks are left alone.
#
# Usage: book-combine.py OUT.adoc LANG TITLE SITE_URL REPO_DIR SPEC VERSION [REPO_DIR SPEC VERSION]...
#   LANG: en or fr. REPO_DIR: the spec repository, generated (glossary, term
#   attributes). The book includes each spec's spec/<LANG>/book.adoc pages, in order.
import os
import re
import sys

VERBATIM = re.compile(r"^(-{4,}|\.{4,}|\+{4,}|/{4,}|`{3}.*)\s*$")
INCLUDE = re.compile(r"^include::([^\[]+\.adoc)\[(.*)\]\s*$")
ID = r"[A-Za-z_][\w.:-]*"
# Inline passthroughs, whose text Asciidoctor does not parse: kept as they are.
PASS = re.compile(r"pass:[a-z,]*\[.*?(?<!\\)\]|\+\+\+.*?\+\+\+|\+\+.*?\+\+|(?<![\w+])\+[^\s+](?:.*?[^\s+])?\+(?![\w+])")
ANCHOR = re.compile(r"\[\[(" + ID + r")(,[^\]]*)?\]\]")
BLOCK_ID = re.compile(r"\[#(" + ID + r")")
INLINE_ANCHOR = re.compile(r"anchor:(" + ID + r")\[")
XREF_MACRO = re.compile(r"xref:([^\[\s]+)\[")
XREF_SHORT = re.compile(r"<<([^>,]+)(,[^>]*)?>>")


def dir_url(rel):
    """URL part of a page path relative to its pages folder, as sitecollect writes it."""
    rel = rel[:-5] if rel.endswith(".adoc") else rel
    if rel == "index":
        return ""
    if rel.endswith("/index"):
        rel = rel[: -len("/index")]
    return rel + "/"


class Spec:
    def __init__(self, repo, spec, lang, site_url):
        self.repo, self.spec, self.lang, self.site_url = repo, spec, lang, site_url
        self.dir = os.path.join(repo, "spec", lang)
        self.prefix = spec + "_"
        self.pages = set()  # page file names the book includes, such as "rules.adoc"

    def page_id(self, page):
        return self.prefix + "page-" + page[:-5].replace("/", "-")

    def target(self, ref):
        """Rewrites a link target. Returns ("id", ID), ("url", URL) or None (unchanged)."""
        path, _, fragment = ref.partition("#")
        if not path:
            return ("id", self.prefix + fragment) if fragment else None
        if "#" not in ref and not path.endswith(".adoc") and "." not in os.path.basename(path) and "/" not in path:
            return ("id", self.prefix + path)  # xref:ID[]
        if not path.endswith(".adoc"):
            return None
        rel = os.path.relpath(os.path.normpath(os.path.join(self.dir, path)), self.repo).replace(os.sep, "/")
        if rel.startswith("spec/%s/" % self.lang) and path in self.pages:
            return ("id", self.prefix + fragment if fragment else self.page_id(path))
        docs = "docs/modules/%s/pages/" % self.lang
        if rel.startswith(docs) and not rel[len(docs):].startswith("jurisdictions/"):
            lang = "/fr" if self.lang == "fr" else ""
            url = "%s%s/%s/guides/%s" % (self.site_url, lang, self.spec, dir_url(rel[len(docs):]))
            return ("url", url + ("#" + fragment if fragment else ""))
        return None

    def rewrite_text(self, text):
        def anchor(m):
            return "[[" + self.prefix + m.group(1) + (m.group(2) or "") + "]]"

        def xref_macro(m):
            t = self.target(m.group(1))
            if t is None:
                return m.group(0)
            return ("xref:" if t[0] == "id" else "link:") + t[1] + "["

        def xref_short(m):
            t = self.target(m.group(1).strip())
            if t is None:
                return m.group(0)
            text = (m.group(2) or "")[1:]
            if t[0] == "url":
                return "link:%s[%s]" % (t[1], text.strip())
            return "<<" + t[1] + ("," + text if m.group(2) else "") + ">>"

        text = ANCHOR.sub(anchor, text)
        text = BLOCK_ID.sub(lambda m: "[#" + self.prefix + m.group(1), text)
        text = INLINE_ANCHOR.sub(lambda m: "anchor:" + self.prefix + m.group(1) + "[", text)
        text = XREF_MACRO.sub(xref_macro, text)
        return XREF_SHORT.sub(xref_short, text)

    def rewrite_line(self, line):
        # Rewrite only outside inline passthroughs.
        out, last = [], 0
        for m in PASS.finditer(line):
            out.append(self.rewrite_text(line[last:m.start()]))
            out.append(m.group(0))
            last = m.end()
        out.append(self.rewrite_text(line[last:]))
        return "".join(out)

    def rewrite_file(self, name, title_id=None):
        path = os.path.join(self.dir, name)
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        out, fence = [], None
        for line in lines:
            bare = line.rstrip("\r")
            if fence:
                out.append(line)
                if bare.strip() == fence:
                    fence = None
                continue
            if VERBATIM.match(bare):
                fence = "```" if bare.startswith("```") else bare.strip()
                out.append(line)
                continue
            if bare.startswith("//"):
                out.append(line)
                continue
            out.append(self.rewrite_line(line))
        if title_id:
            first = out[0].lstrip("﻿")
            if not first.startswith("= "):
                sys.exit("%s: the first line must be the page title (\"= ...\")" % path)
            out[0] = "[#%s]\n%s" % (title_id, first)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out))


def read_book(spec):
    """Returns the title of spec/<lang>/book.adoc and its includes (page, attributes)."""
    path = os.path.join(spec.dir, "book.adoc")
    with open(path, encoding="utf-8") as f:
        lines = [l.rstrip("\r\n") for l in f]
    if not lines or not lines[0].lstrip("﻿").startswith("= "):
        sys.exit("%s: the first line must be the book title (\"= ...\")" % path)
    title, includes = lines[0].lstrip("﻿")[2:].strip(), []
    for n, line in enumerate(lines[1:], 2):
        if not line.strip() or re.match(r"^:[\w-]+!?:", line) or line.startswith("//"):
            continue
        m = INCLUDE.match(line)
        if not m or "/" in m.group(1):
            sys.exit("%s:%d: a book holds only header attributes and includes of its pages, not \"%s\"" % (path, n, line))
        includes.append((m.group(1), m.group(2)))
    if not includes:
        sys.exit("%s: the book includes no page" % path)
    return title, includes


def main(argv):
    if len(argv) < 8 or (len(argv) - 5) % 3:
        sys.exit("usage: book-combine.py OUT.adoc LANG TITLE SITE_URL REPO_DIR SPEC VERSION [REPO_DIR SPEC VERSION]...")
    out, lang, title, site_url = argv[1:5]
    if lang not in ("en", "fr"):
        sys.exit("LANG must be en or fr")
    base = os.path.dirname(os.path.abspath(out))
    book = ["= " + title, ":doctype: book", ":toc:", ""]
    for i in range(5, len(argv), 3):
        repo, name, version = os.path.abspath(argv[i]), argv[i + 1], argv[i + 2]
        spec = Spec(repo, name, lang, site_url.rstrip("/"))
        part_title, includes = read_book(spec)
        spec.pages = {page for page, _ in includes}
        for page in sorted(n for n in os.listdir(spec.dir) if n.endswith(".adoc") and n != "book.adoc"):
            spec.rewrite_file(page, spec.page_id(page) if page in spec.pages else None)
        rel = os.path.relpath(spec.dir, base).replace(os.sep, "/")
        # The part title, then its version; images resolve from the spec's own folder.
        book += ["[#%spart]" % spec.prefix, "= " + part_title, "", ":imagesdir: " + rel, "",
                 "Version " + version, ""]
        for page, attrs in includes:
            book += ["include::%s/%s[%s]" % (rel, page, attrs), ""]
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(book))


if __name__ == "__main__":
    main(sys.argv)
