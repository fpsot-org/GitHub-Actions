// SPDX-License-Identifier: Apache-2.0

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/doccheck"
)

func TestRun(t *testing.T) {
	root := t.TempDir()
	for _, p := range doccheck.Required {
		os.MkdirAll(filepath.Dir(filepath.Join(root, p)), 0o755)
		os.WriteFile(filepath.Join(root, p), []byte("= T\n\n== Document history\n"), 0o644)
	}
	for _, l := range []string{"en", "fr"} {
		os.WriteFile(filepath.Join(root, "spec", l, "book.adoc"), []byte("= B\n\ninclude::glossary.adoc[]\n"), 0o644)
	}
	os.WriteFile(filepath.Join(root, "spec/fr/index.adoc"), []byte("= T\n\n== Historique du document\n"), 0o644)
	var out bytes.Buffer
	if code := run([]string{"-root", root}, &out, &out); code != 0 {
		t.Fatalf("exit %d: %s", code, out.String())
	}
	os.MkdirAll(filepath.Join(root, "docs/modules/en/pages"), 0o755)
	os.WriteFile(filepath.Join(root, "docs/modules/en/pages/a.adoc"), []byte("= A\n\nimage::x.svg[]\n\n== Document history\n"), 0o644)
	out.Reset()
	if code := run([]string{"-root", root}, &out, &out); code != 1 || !strings.Contains(out.String(), "page-type") || !strings.Contains(out.String(), "text alternative") {
		t.Fatalf("exit %d: %s", code, out.String())
	}
}

func TestRunReferencesFlag(t *testing.T) {
	root := t.TempDir()
	for _, p := range doccheck.Required {
		os.MkdirAll(filepath.Dir(filepath.Join(root, p)), 0o755)
		os.WriteFile(filepath.Join(root, p), []byte("= T\n\n== Document history\n"), 0o644)
	}
	for _, l := range []string{"en", "fr"} {
		os.WriteFile(filepath.Join(root, "spec", l, "book.adoc"), []byte("= B\n\ninclude::glossary.adoc[]\n"), 0o644)
	}
	os.WriteFile(filepath.Join(root, "spec/fr/index.adoc"), []byte("= T\n\n== Historique du document\n"), 0o644)
	os.WriteFile(filepath.Join(root, "spec/en/index.adoc"), []byte("= T\n\nSee https://www.rfc-editor.org/info/rfc9110.\n\n----\nx\n----\n\n== Document history\n"), 0o644)
	var out bytes.Buffer
	if code := run([]string{"-root", root}, &out, &out); code != 0 {
		t.Fatalf("without -references: exit %d: %s", code, out.String())
	}
	out.Reset()
	if code := run([]string{"-root", root, "-references"}, &out, &out); code != 1 || !strings.Contains(out.String(), "rfc9110") || !strings.Contains(out.String(), "language") {
		t.Fatalf("with -references: exit %d: %s", code, out.String())
	}
}
