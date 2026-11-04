#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Converts an ODT file to a tagged PDF/UA-1 and PDF/A-2b file with LibreOffice.
# Unlike "soffice --convert-to", it first updates the table of contents and other
# indexes, which a headless conversion leaves empty. For PDF/UA-1, it also gives each
# image its text alternative (7.3) and each link a description (7.18.5).
#
# Usage: odt-to-pdf.py IN.odt OUT.pdf PROFILE_DIR [ALTS.json]
#   ALTS.json: the text alternatives of the images, in document order.
# Needs LibreOffice and its Python bridge (python3-uno).
import json
import os
import re
import subprocess
import sys
import time

import uno
from com.sun.star.beans import PropertyValue


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
    for i, name in enumerate(sorted(graphics.getElementNames(), key=number)):
        if i < len(alts) and alts[i]:
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


def main(src, out, profile, alts_file=None):
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
        alts = json.load(open(alts_file, encoding="utf-8")) if alts_file else []
        set_alternatives(doc, alts)
        rename_standard_styles(doc)
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
    if len(sys.argv) not in (4, 5):
        sys.exit("usage: odt-to-pdf.py IN.odt OUT.pdf PROFILE_DIR [ALTS.json]")
    main(*sys.argv[1:])
