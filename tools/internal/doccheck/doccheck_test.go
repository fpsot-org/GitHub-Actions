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

const refHist = "\n== Document history\n\n|===\n|Version |Date |Change\n|===\n"

func TestReferencesMissingEntry(t *testing.T) {
	root := tree(t, map[string]string{"spec/en/http.adoc": "= HTTP\n\nA server follows link:https://www.rfc-editor.org/info/rfc9110[RFC 9110].\n" + refHist})
	one(t, References([]string{filepath.Join(root, "spec/en/http.adoc")}), "https://www.rfc-editor.org/info/rfc9110")
}

func TestReferencesOK(t *testing.T) {
	root := tree(t, map[string]string{"spec/en/http.adoc": "= HTTP\n\nA server follows link:https://www.rfc-editor.org/info/rfc9110[RFC 9110].\n\n== References\n\n=== Normative\n\n* link:https://www.rfc-editor.org/info/rfc9110[RFC 9110, HTTP Semantics], 2022-06. link:https://web.archive.org/web/2026/https://www.rfc-editor.org/info/rfc9110[Archived copy]\n" + refHist})
	if got := References([]string{filepath.Join(root, "spec/en/http.adoc")}); len(got) != 0 {
		t.Fatalf("want no findings, got %+v", got)
	}
}

func TestReferencesIgnores(t *testing.T) {
	body := "= Page\n\nSee link:https://fpsot.org/doc/[the doc spec], link:https://github.com/fpsot-org/x[the repo] and link:https://web.archive.org/web/2026/https://x.org/[a copy].\nThe type is `https://www.iana.org/not-a-citation`.\n\n[source,http]\n----\nGET https://api.example.com/v1/parties\n----\n" + refHist
	root := tree(t, map[string]string{"spec/en/page.adoc": body})
	if got := References([]string{filepath.Join(root, "spec/en/page.adoc")}); len(got) != 0 {
		t.Fatalf("want no findings, got %+v", got)
	}
}

func TestReferencesNoArchive(t *testing.T) {
	root := tree(t, map[string]string{"spec/en/http.adoc": "= HTTP\n\nSee link:https://www.rfc-editor.org/info/rfc9110[RFC 9110].\n\n== References\n\n=== Normative\n\n* link:https://www.rfc-editor.org/info/rfc9110[RFC 9110, HTTP Semantics], 2022-06.\n" + refHist})
	one(t, References([]string{filepath.Join(root, "spec/en/http.adoc")}), "archived copy")
}

func TestReferencesPlacement(t *testing.T) {
	root := tree(t, map[string]string{"spec/en/http.adoc": "= HTTP\n\nSee link:https://www.rfc-editor.org/info/rfc9110[RFC 9110].\n\n== References\n\n=== Normative\n\n* link:https://www.rfc-editor.org/info/rfc9110[RFC 9110], 2022-06. link:https://web.archive.org/web/2026/x[Archived copy]\n\n== Notes\n\nMore.\n" + refHist})
	one(t, References([]string{filepath.Join(root, "spec/en/http.adoc")}), "just before")
}

func TestReferencesFrench(t *testing.T) {
	hist := "\n== Historique du document\n\n|===\n|Version |Date |Changement\n|===\n"
	root := tree(t, map[string]string{"spec/fr/http.adoc": "= HTTP\n\nVoir link:https://www.rfc-editor.org/info/rfc9110[RFC 9110].\n\n== Références\n\n=== Références normatives\n\n* link:https://www.rfc-editor.org/info/rfc9110[RFC 9110], 2022-06. link:https://web.archive.org/web/2026/x[Copie archivée]\n" + hist})
	if got := References([]string{filepath.Join(root, "spec/fr/http.adoc")}); len(got) != 0 {
		t.Fatalf("want no findings, got %+v", got)
	}
}

func TestCodeLanguage(t *testing.T) {
	root := tree(t, map[string]string{"spec/en/code.adoc": "= Code\n\n[source,json]\n----\n{}\n----\n\n[source]\n----\nx\n----\n\n----\ny\n----\n" + refHist})
	got := CodeLanguage([]string{filepath.Join(root, "spec/en/code.adoc")})
	if len(got) != 2 {
		t.Fatalf("want 2 findings, got %+v", got)
	}
}

func TestReferencesUnlinkedRFC(t *testing.T) {
	body := "= HTTP\n\nA server follows {abbr-rfc} 9110 and RFC 9457.\nIt also follows link:https://www.rfc-editor.org/info/rfc7396[RFC 7396].\n\n== References\n\n=== Normative\n\n* link:https://www.rfc-editor.org/info/rfc7396[RFC 7396], 2014-10. link:https://web.archive.org/web/2026/x[Archived copy]\n" + refHist
	root := tree(t, map[string]string{"spec/en/http.adoc": body})
	got := References([]string{filepath.Join(root, "spec/en/http.adoc")})
	if len(got) != 2 || !strings.Contains(got[0].Msg, "9110") || !strings.Contains(got[1].Msg, "9457") {
		t.Fatalf("want 2 unlinked RFC findings, got %+v", got)
	}
}

func TestReferencesCommitPinnedGitHub(t *testing.T) {
	pinned := "https://github.com/cloudevents/spec/blob/fc1f6f31f5f011a72183f1bcea20c987cb683ade/cloudevents/spec.md"
	tag := "https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md"
	body := "= Events\n\nSee link:" + pinned + "[CloudEvents] and link:" + tag + "[CloudEvents].\n\n== References\n\n=== Normative\n\n* link:" + pinned + "[CloudEvents 1.0.2], CNCF, 2022-02.\n* link:" + tag + "[CloudEvents 1.0.2], CNCF, 2022-02.\n" + refHist
	root := tree(t, map[string]string{"spec/en/events.adoc": body})
	// The commit-pinned link cannot change, so it is its own archived copy; a tag can move.
	one(t, References([]string{filepath.Join(root, "spec/en/events.adoc")}), "archived copy")
}

func TestReferencesURLMatching(t *testing.T) {
	body := "= HTTP\n\nSee https://www.rfc-editor.org/info/rfc9110. Also (https://semver.org/spec/v2.0.0.html) and link:https://www.rfc-editor.org/rfc/rfc9110#section-9[section 9].\nSee xref:other.adoc[RFC 7396] and <<x,RFC 9457>>.\n\n== References\n\n=== Normative\n\n* link:https://www.rfc-editor.org/info/rfc9110[RFC 9110], 2022-06. link:https://web.archive.org/web/1/x[Archived copy]\n* link:https://semver.org/spec/v2.0.0.html[SemVer]. link:https://web.archive.org/web/1/y[Archived copy]\n* link:https://www.rfc-editor.org/rfc/rfc9110[RFC 9110], 2022-06. link:https://web.archive.org/web/1/z[Archived copy]\n\n== Document history\n\n|===\n|Version |Date |Change\n|0.1.0 |2026-11-02 |Follows RFC 8174 and https://example.org/x.\n|0.1.1 |2026-11-03 |See https://www.w3.org/TR/old/.\n|===\n"
	root := tree(t, map[string]string{"spec/en/http.adoc": body})
	if got := References([]string{filepath.Join(root, "spec/en/http.adoc")}); len(got) != 0 {
		t.Fatalf("want no findings (punctuation trimmed, fragment ignored, xref and history skipped), got %+v", got)
	}
}

func TestCodeLanguageForms(t *testing.T) {
	root := tree(t, map[string]string{"spec/en/code.adoc": "= Code\n\n[source%linenums,json]\n----\n{}\n----\n\n[,yaml]\n----\na: 1\n----\n\n[source,json]\n.Example\n----\n{}\n----\n\n[source%linenums]\n----\nx\n----\n" + refHist})
	got := CodeLanguage([]string{filepath.Join(root, "spec/en/code.adoc")})
	if len(got) != 1 || got[0].Line != 20 {
		t.Fatalf("want 1 finding at line 20, got %+v", got)
	}
}
