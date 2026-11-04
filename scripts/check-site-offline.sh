#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks that a built site makes no request to another host and runs no script
# other than the light/dark theme toggle. Links (<a href>) and the canonical and
# hreflang <link> elements may point anywhere: browsers do not fetch them.
#
# Usage: check-site-offline.sh SITE_DIR
set -euo pipefail
site=${1:?usage: check-site-offline.sh SITE_DIR}
python3 -I - "$site" <<'PY'
import os, re, sys
from html.parser import HTMLParser

site = sys.argv[1]
external = re.compile(r'^\s*(https?:)?//', re.I)
theme_js = re.compile(r'(^|/)assets/js/theme\.js$')
problems = []

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path, self.in_script, self.script = path, False, ''
    def report(self, msg):
        problems.append(f'{self.path}:{self.getpos()[0]}: {msg}')
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        for key in ('src', 'poster', 'data'):
            if a.get(key) and external.match(a[key]):
                self.report(f'<{tag} {key}="{a[key]}"> loads from another host')
        if a.get('srcset') and any(external.match(p.strip()) for p in a['srcset'].split(',')):
            self.report(f'<{tag} srcset> loads from another host')
        if tag == 'link' and a.get('href') and external.match(a['href']):
            rel = (a.get('rel') or '').lower().split()
            if not set(rel) <= {'canonical', 'alternate'}:
                self.report(f'<link rel="{a.get("rel")}" href="{a["href"]}"> loads from another host')
        if tag == 'script':
            if a.get('src'):
                if not theme_js.search(a['src']):
                    self.report(f'<script src="{a["src"]}"> is not the theme toggle')
            else:
                self.in_script, self.script = True, ''
    def handle_data(self, data):
        if self.in_script:
            self.script += data
    def handle_endtag(self, tag):
        if tag == 'script' and self.in_script:
            self.in_script = False
            if self.script.strip() and 'fpsot-color-scheme' not in self.script:
                self.report('inline <script> is not the theme toggle')

css_url = re.compile(r'(@import\s+["\']|url\(\s*["\']?)\s*(https?:)?//', re.I)
for root, _, files in os.walk(site):
    for name in files:
        path = os.path.join(root, name)
        rel = os.path.relpath(path, os.path.dirname(os.path.abspath(site)))
        if name.endswith('.html'):
            p = Page(rel)
            p.feed(open(path, encoding='utf-8', errors='replace').read())
        elif name.endswith('.css'):
            for n, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
                if css_url.search(line):
                    problems.append(f'{rel}:{n}: CSS loads from another host')
for p in problems:
    print(p)
if problems:
    print(f'{len(problems)} external request(s) or extra script(s) found', file=sys.stderr)
    sys.exit(1)
PY
