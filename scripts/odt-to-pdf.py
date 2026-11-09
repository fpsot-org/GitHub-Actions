#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Converts an ODT file to a tagged PDF/UA-1 and PDF/A-2b file with LibreOffice.
# Unlike "soffice --convert-to", it first updates the table of contents and other
# indexes, which a headless conversion leaves empty. For PDF/UA-1, it also gives each
# image its text alternative (7.3) and each link a description (7.18.5). With a
# notice, it puts the legal notice on a page of its own after the title page.
#
# Usage: odt-to-pdf.py IN.odt OUT.pdf PROFILE_DIR [ALTS.json [NOTICE.json]]
#   ALTS.json: the text alternatives of the images, in document order.
#   NOTICE.json: the legal notice, as spec-legal.py writes it.
# Needs LibreOffice and its Python bridge (python3-uno).
import json
import os
import re
import subprocess
import sys
import time

import uno
from com.sun.star.beans import PropertyValue
from com.sun.star.style.BreakType import PAGE_AFTER, PAGE_BEFORE
from com.sun.star.text.ControlCharacter import LINE_BREAK, PARAGRAPH_BREAK


def prop(name, value):
    p = PropertyValue()
    p.Name, p.Value = name, value
    return p


def set_alternatives(doc, alts):
    """Gives image N of the document (pandoc names them img1, img2, ...) alts[N-1]."""
    graphics = doc.getGraphicObjects()
    def number(name):
        m = re.search(r"(\d+)$", name)
        return int(m.group(1)) if m else 0
    names = sorted(graphics.getElementNames(), key=number)
    if len(alts) != len(names):
        # Matching by position would give some images the alternative of another one.
        sys.exit("%d text alternatives for %d image%s: pandoc dropped or added an image"
                 % (len(alts), len(names), "" if len(names) == 1 else "s"))
    for i, name in enumerate(names):
        if alts[i]:
            g = graphics.getByName(name)
            g.Title = alts[i]
            g.Description = alts[i]


# Standard structure types of ISO 32000-1, 14.8.4. LibreOffice 24.2 writes a RoleMap
# entry for each paragraph style it does not know, and the built-in "Figure" style,
# which pandoc uses for images, comes out as "/Figure /P": a remapped standard type,
# which PDF/UA-1 7.1 forbids. Paragraphs of such styles move to a copy of the style.
# "Caption" is left alone: LibreOffice maps it to the standard Caption type.
STANDARD_TYPES = {
    "Document", "Part", "Art", "Sect", "Div", "BlockQuote", "Caption", "TOC", "TOCI",
    "Index", "NonStruct", "Private", "P", "H", "H1", "H2", "H3", "H4", "H5", "H6", "L",
    "LI", "Lbl", "LBody", "Table", "TR", "TH", "TD", "THead", "TBody", "TFoot", "Span",
    "Quote", "Note", "Reference", "BibEntry", "Code", "Link", "Annot", "Ruby", "RB",
    "RT", "RP", "Warichu", "WT", "WP", "Figure", "Formula", "Form",
} - {"Caption"}


def paragraphs(text):
    """Yields every paragraph of a text, recursing into tables."""
    items = text.createEnumeration()
    while items.hasMoreElements():
        item = items.nextElement()
        if item.supportsService("com.sun.star.text.TextTable"):
            for cell in item.getCellNames():
                yield from paragraphs(item.getCellByName(cell).getText())
        else:
            yield item


def rename_standard_styles(doc):
    """Moves paragraphs off styles named after a standard structure type."""
    styles = doc.getStyleFamilies().getByName("ParagraphStyles")
    renamed = {}
    for name in styles.getElementNames():
        style = styles.getByName(name)
        if name in STANDARD_TYPES:
            new = name + " paragraph"
            if not styles.hasByName(new):
                copy = doc.createInstance("com.sun.star.style.ParagraphStyle")
                styles.insertByName(new, copy)
                copy.ParentStyle = name
            renamed[name] = new
    if renamed:
        for para in paragraphs(doc.getText()):
            if para.ParaStyleName in renamed:
                para.ParaStyleName = renamed[para.ParaStyleName]


def name_links(text):
    """Names each hyperlink that has no name after its text, recursing into tables."""
    paragraphs = text.createEnumeration()
    while paragraphs.hasMoreElements():
        para = paragraphs.nextElement()
        if para.supportsService("com.sun.star.text.TextTable"):
            for cell in para.getCellNames():
                name_links(para.getCellByName(cell).getText())
            continue
        # A table of contents line links its text and its page number to the same
        # place: the page number takes the name of the text before it.
        names = {}
        portions = para.createEnumeration()
        while portions.hasMoreElements():
            portion = portions.nextElement()
            url = portion.HyperLinkURL
            if not url:
                continue
            if not portion.HyperLinkName:
                portion.HyperLinkName = names.get(url) or portion.getString().strip() or url
            names.setdefault(url, portion.HyperLinkName)


def keep_link_paragraphs_together(text):
    """Keeps each paragraph that holds a link on one page. A link that breaks across
    two pages leaves its second part out of the tags (PDF/UA-1, clause 7.18.5).
    Specification paragraphs are short, so keeping them whole costs little space."""
    for para in paragraphs(text):
        portions = para.createEnumeration()
        while portions.hasMoreElements():
            if portions.nextElement().HyperLinkURL:
                para.ParaSplit = False
                break


def keep_rows_together(doc):
    """Keep each table row on one page. A row that breaks across two pages leaves
    the second part of its links out of the tags (PDF/UA-1, clause 7.18.5)."""
    tables = doc.getTextTables()
    for t in range(tables.getCount()):
        rows = tables.getByIndex(t).getRows()
        for r in range(rows.getCount()):
            rows.getByIndex(r).IsSplitAllowed = False


# The paragraphs of the title block, which pandoc writes before the contents.
TITLE_STYLES = {"Title", "Subtitle", "Author", "Date"}


def insert_notice(doc, notice):
    """Puts the notice paragraphs on a page of their own, after the title block and
    before the table of contents. Links keep their address; name_links names them."""
    text = doc.getText()
    items = text.createEnumeration()
    last = None
    while items.hasMoreElements():
        item = items.nextElement()
        if not item.supportsService("com.sun.star.text.Paragraph") or item.ParaStyleName not in TITLE_STYLES:
            break
        last = item
    if last is None:
        sys.exit("no title block to put the notice after")
    cursor = text.createTextCursorByRange(last.getEnd())
    for i, runs in enumerate(notice["paragraphs"]):
        text.insertControlCharacter(cursor, PARAGRAPH_BREAK, False)
        cursor.ParaStyleName = "Text body"
        cursor.BreakType = PAGE_BEFORE if i == 0 else PAGE_AFTER if i == len(notice["paragraphs"]) - 1 else 0
        for run in runs:
            for n, piece in enumerate(run["text"].split("\n")):
                if n:
                    text.insertControlCharacter(cursor, LINE_BREAK, False)
                if not piece:
                    continue
                start = cursor.getStart()
                text.insertString(cursor, piece, False)
                span = text.createTextCursorByRange(start)
                span.gotoRange(cursor.getEnd(), True)
                span.HyperLinkURL = run.get("href", "")
                span.CharWeight = 150.0 if i == 0 else 100.0  # the first line names the document
    if len(notice["paragraphs"]) == 1:
        cursor.BreakType = PAGE_BEFORE


def main(src, out, profile, alts_file=None, notice_file=None):
    pipe = "fpsot_pdf_%d" % os.getpid()
    office = subprocess.Popen([
        "soffice", "--headless", "--invisible", "--nologo", "--norestore",
        "-env:UserInstallation=" + uno.systemPathToFileUrl(os.path.abspath(profile)),
        "--accept=pipe,name=%s;urp;StarOffice.ComponentContext" % pipe,
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        resolver = uno.getComponentContext().ServiceManager.createInstanceWithContext(
            "com.sun.star.bridge.UnoUrlResolver", uno.getComponentContext())
        ctx = None
        for _ in range(120):
            try:
                ctx = resolver.resolve("uno:pipe,name=%s;urp;StarOffice.ComponentContext" % pipe)
                break
            except Exception:
                time.sleep(0.5)
        if ctx is None:
            sys.exit("LibreOffice did not start")
        desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
        doc = desktop.loadComponentFromURL(
            uno.systemPathToFileUrl(os.path.abspath(src)), "_blank", 0, (prop("Hidden", True),))
        if alts_file:
            set_alternatives(doc, json.load(open(alts_file, encoding="utf-8")))
        if notice_file:
            insert_notice(doc, json.load(open(notice_file, encoding="utf-8")))
        rename_standard_styles(doc)
        keep_rows_together(doc)
        keep_link_paragraphs_together(doc.getText())
        indexes = doc.getDocumentIndexes()
        for i in range(indexes.getCount()):
            indexes.getByIndex(i).update()
        # After the update: the table of contents is made of links too.
        name_links(doc.getText())
        filter_data = uno.Any("[]com.sun.star.beans.PropertyValue", (
            prop("UseTaggedPDF", True),
            prop("PDFUACompliance", True),
            prop("SelectPdfVersion", 2),
        ))
        doc.storeToURL(uno.systemPathToFileUrl(os.path.abspath(out)), (
            prop("FilterName", "writer_pdf_Export"),
            prop("FilterData", filter_data),
        ))
        doc.close(True)
        try:
            desktop.terminate()
        except Exception:
            pass
    finally:
        try:
            office.wait(timeout=30)
        except subprocess.TimeoutExpired:
            office.kill()


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5, 6):
        sys.exit("usage: odt-to-pdf.py IN.odt OUT.pdf PROFILE_DIR [ALTS.json [NOTICE.json]]")
    main(*sys.argv[1:])
