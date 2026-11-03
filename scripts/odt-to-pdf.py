#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Converts an ODT file to a tagged PDF/UA-1 and PDF/A-2b file with LibreOffice.
# Unlike "soffice --convert-to", it first updates the table of contents and other
# indexes, which a headless conversion leaves empty.
#
# Usage: odt-to-pdf.py IN.odt OUT.pdf PROFILE_DIR
# Needs LibreOffice and its Python bridge (python3-uno).
import os
import subprocess
import sys
import time

import uno
from com.sun.star.beans import PropertyValue


def prop(name, value):
    p = PropertyValue()
    p.Name, p.Value = name, value
    return p


def main(src, out, profile):
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
        indexes = doc.getDocumentIndexes()
        for i in range(indexes.getCount()):
            indexes.getByIndex(i).update()
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
    if len(sys.argv) != 4:
        sys.exit("usage: odt-to-pdf.py IN.odt OUT.pdf PROFILE_DIR")
    main(*sys.argv[1:])
