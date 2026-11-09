#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Puts the rights statement of a legal notice into the XMP metadata of a PDF:
# dc:rights (the statement), xmpRights:Marked (true: the document carries rights)
# and xmpRights:WebStatement (the license URL). Both schemas are predefined in XMP,
# so the file stays PDF/A-2b; the rest of the file, its tags included, is kept.
#
# Usage: pdf-rights.py FILE.pdf NOTICE.json   (NOTICE.json as spec-legal.py writes it)
# Needs pikepdf.
import json
import sys

import pikepdf

if len(sys.argv) != 3:
    sys.exit("usage: pdf-rights.py FILE.pdf NOTICE.json")
path, notice = sys.argv[1], json.load(open(sys.argv[2], encoding="utf-8"))
with pikepdf.open(path, allow_overwriting_input=True) as pdf:
    # The Info dictionary has no rights entry: only the XMP changes, and the producer
    # stays LibreOffice.
    with pdf.open_metadata(set_pikepdf_as_editor=False, update_docinfo=False) as meta:
        meta["dc:rights"] = notice["rights"]
        meta["xmpRights:Marked"] = "True"
        if notice.get("rights_url"):
            meta["xmpRights:WebStatement"] = notice["rights_url"]
    pdf.save(path)
