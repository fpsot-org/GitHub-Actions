// SPDX-License-Identifier: Apache-2.0

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const data = "../../internal/termbase/testdata/"

func TestExitCodes(t *testing.T) {
	dir := t.TempDir()
	attrs := filepath.Join(dir, "_fpsot-terms.adoc")
	gloss := filepath.Join(dir, "glossary.adoc")
	var out, errb bytes.Buffer
	code := run([]string{"-termbase", data + "terms.yaml", "-lang", "en", "-attrs", attrs, "-glossary", gloss, data + "pages/good.adoc"}, &out, &errb)
	if code != 0 {
		t.Fatalf("good page: exit %d, stdout %q, stderr %q", code, out.String(), errb.String())
	}
	a, err := os.ReadFile(attrs)
	if err != nil || !strings.Contains(string(a), ":abbr-api:") {
		t.Fatalf("attributes not written: %v", err)
	}
	g, err := os.ReadFile(gloss)
	if err != nil || !strings.Contains(string(g), "[[gl-api]]") || strings.Contains(string(g), "gl-pdf") {
		t.Fatalf("glossary wrong: %v\n%s", err, g)
	}

	out.Reset()
	code = run([]string{"-termbase", data + "terms.yaml", "-lang", "en", "-attrs", attrs, data + "pages/bad-order.adoc"}, &out, &errb)
	if code != 1 || !strings.Contains(out.String(), "bad-order.adoc:3:") {
		t.Fatalf("bad page: exit %d, stdout %q", code, out.String())
	}
}

func TestDirectoryArgumentSkipsPartials(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "page.adoc"), []byte("= P\n\nThe {abbr-api-first}.\n"), 0o644)
	os.WriteFile(filepath.Join(dir, "_partial.adoc"), []byte("{abbr-nope}\n"), 0o644)
	var out, errb bytes.Buffer
	code := run([]string{"-termbase", data + "terms.yaml", "-lang", "fr", "-attrs", filepath.Join(dir, "_fpsot-terms.adoc"), dir}, &out, &errb)
	if code != 0 {
		t.Fatalf("exit %d: %s %s", code, out.String(), errb.String())
	}
}

func TestBadArguments(t *testing.T) {
	var out, errb bytes.Buffer
	if code := run([]string{"-termbase", data + "terms.yaml", "-lang", "de", "-attrs", "x"}, &out, &errb); code != 2 {
		t.Fatalf("bad lang: exit %d", code)
	}
	if code := run([]string{"-lang", "en"}, &out, &errb); code != 2 {
		t.Fatalf("missing flags: exit %d", code)
	}
}
