// SPDX-License-Identifier: Apache-2.0

package doccheck

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// tree writes files (relative path → content) under a temp dir and returns it.
func tree(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for p, body := range files {
		full := filepath.Join(root, p)
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func one(t *testing.T, got []Finding, want string) {
	t.Helper()
	if len(got) != 1 || !strings.Contains(got[0].Msg, want) {
		t.Fatalf("want one finding containing %q, got %+v", want, got)
	}
}

func TestRequiredFiles(t *testing.T) {
	files := map[string]string{}
	for _, p := range Required {
		files[p] = "x\n"
	}
	if f := RequiredFiles(tree(t, files)); len(f) != 0 {
		t.Fatalf("complete repo has findings: %+v", f)
	}
	delete(files, "AGENTS.md")
	one(t, RequiredFiles(tree(t, files)), "AGENTS.md")
	if len(Required) != 19 {
		t.Fatalf("Required has %d entries, the plan lists 19", len(Required))
	}
}

func TestHistory(t *testing.T) {
	root := tree(t, map[string]string{
		"spec/en/notes.adoc":    "= A\n\n== Rules\n\ntext\n\n== Notes\n\ntext\n",
		"spec/fr/ok.adoc":       "= A\n\n== Règles\n\n== Historique du document\n\n|===\n|===\n",
		"spec/en/ok.adoc":       "= A\n\n== Document history\n\n----\n== Not a section\n----\n",
		"spec/en/none.adoc":     "= A\n\ntext\n",
		"spec/en/glossary.adoc": "= Glossary\n",
		"spec/en/book.adoc":     "= Book\n",
		"spec/en/_partial.adoc": "x\n",
		"docs/modules/en/pages/jurisdictions/x/index.adoc": "= J\n",
	})
	var files []string
	filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if !d.IsDir() {
			files = append(files, p)
		}
		return nil
	})
	got := History(files)
	if len(got) != 2 {
		t.Fatalf("want findings for notes.adoc and none.adoc only, got %+v", got)
	}
	for _, f := range got {
		if !strings.HasSuffix(f.File, "notes.adoc") && !strings.HasSuffix(f.File, "none.adoc") {
			t.Fatalf("unexpected finding %+v", f)
		}
		if !strings.Contains(f.Msg, "Document history") {
			t.Fatalf("message does not name the heading: %+v", f)
		}
	}
}

func TestPageType(t *testing.T) {
	root := tree(t, map[string]string{
		"docs/modules/en/pages/a.adoc": "= A\n:page-type: how-to\n",
		"docs/modules/en/pages/b.adoc": "= B\n",
		"docs/modules/fr/pages/c.adoc": "= C\n:page-type: guide\n",
	})
	got := PageType([]string{
		filepath.Join(root, "docs/modules/en/pages/a.adoc"),
		filepath.Join(root, "docs/modules/en/pages/b.adoc"),
		filepath.Join(root, "docs/modules/fr/pages/c.adoc"),
	})
	if len(got) != 2 || !strings.Contains(got[1].Msg, `"guide"`) {
		t.Fatalf("want findings for b (missing) and c (guide), got %+v", got)
	}
}

func TestImageAlt(t *testing.T) {
	root := tree(t, map[string]string{"a.adoc": strings.Join([]string{
		"image::a.svg[]",
		"image::b.svg[Branch diagram]",
		"Inline image:c.svg[] here.",
		"image::d.svg[width=200]",
		`image::e.svg[alt="Flow",width=200]`,
		"----",
		"image::f.svg[]",
		"----",
	}, "\n")})
	got := ImageAlt([]string{filepath.Join(root, "a.adoc")})
	lines := []int{}
	for _, f := range got {
		lines = append(lines, f.Line)
	}
	if len(got) != 3 || lines[0] != 1 || lines[1] != 3 || lines[2] != 4 {
		t.Fatalf("want findings on lines 1, 3, 4, got %+v", got)
	}
}

func TestBook(t *testing.T) {
	root := tree(t, map[string]string{
		"good.adoc": "= B\n:doctype: book\n\ninclude::index.adoc[leveloffset=+1]\n\ninclude::glossary.adoc[leveloffset=+1]\n",
		"bad.adoc":  "= B\n\ninclude::glossary.adoc[]\n\ninclude::git.adoc[]\n",
	})
	if f := Book(filepath.Join(root, "good.adoc")); len(f) != 0 {
		t.Fatalf("good book: %+v", f)
	}
	one(t, Book(filepath.Join(root, "bad.adoc")), "glossary.adoc")
}
