#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Checks that every link of a DocBook book leads somewhere: to an ID of the book, or
# to a web address. Asciidoctor only reports a link to a missing ID at the info
# level, and turns a link to a file it does not hold into a relative link, which
# leads nowhere in a PDF.
#
# Usage: book-links.py BOOK.xml
import re
import sys
import xml.etree.ElementTree as ET

XML_ID = "{http://www.w3.org/XML/1998/namespace}id"
XLINK = "{http://www.w3.org/1999/xlink}href"

root = ET.parse(sys.argv[1]).getroot()
ids = {e.get(XML_ID) for e in root.iter() if e.get(XML_ID)}
bad = set()
for e in root.iter():
    if e.get("linkend") and e.get("linkend") not in ids:
        bad.add("link to the missing ID " + e.get("linkend"))
    if e.get(XLINK) and not re.match(r"(https?|mailto):", e.get(XLINK)):
        bad.add("link to the file " + e.get(XLINK) + ", which is not in the book")
for b in sorted(bad):
    print("error: %s: %s" % (sys.argv[1], b), file=sys.stderr)
sys.exit(1 if bad else 0)
