// SPDX-License-Identifier: Apache-2.0

package site

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const fixture = "testdata/spec"

func TestRouteTable(t *testing.T) {
	cases := map[string]string{
		"spec/en/index.adoc":                                           "/writing/",
		"spec/fr/index.adoc":                                           "/fr/writing/",
		"spec/en/keywords.adoc":                                        "/writing/keywords/",
		"spec/fr/book.adoc":                                            "/fr/writing/book/",
		"spec/en/glossary.adoc":                                        "/writing/glossary/",
		"docs/modules/en/pages/guide.adoc":                             "/writing/guides/guide/",
		"docs/modules/fr/pages/jurisdictions/keywords/index.adoc":      "/fr/writing/compare/keywords/",
		"docs/modules/en/pages/jurisdictions/keywords/region-019.adoc": "/writing/compare/keywords/region-019/",
		"docs/modules/en/pages/jurisdictions/keywords/ca/index.adoc":   "/writing/compare/keywords/ca/",
		"docs/modules/fr/pages/jurisdictions/keywords/ca/qc.adoc":      "/fr/writing/compare/keywords/ca/qc/",
	}
	for src, want := range cases {
		p, ok, err := Route("writing", "/writing", src)
		if err != nil || !ok || p.URL != want {
			t.Errorf("Route(%q) = %+v, %v, %v; want URL %q", src, p, ok, err, want)
		}
	}
	for _, src := range []string{"spec/en/_fpsot-terms.adoc", "docs/modules/en/pages/_fpsot-terms.adoc", "spec/en/x.png", "README.adoc"} {
		if _, ok, err := Route("writing", "/writing", src); ok || err != nil {
			t.Errorf("Route(%q) should not be a page (ok=%v, err=%v)", src, ok, err)
		}
	}
}

func TestRouteFranceInEnglish(t *testing.T) {
	p, ok, err := Route("writing", "/writing", "docs/modules/en/pages/jurisdictions/keywords/fr/index.adoc")
	if err != nil || !ok || p.Lang != "en" || p.URL != "/writing/compare/keywords/fr/" {
		t.Fatalf("got %+v, %v, %v", p, ok, err)
	}
}

func TestRouteReservedName(t *testing.T) {
	for _, src := range []string{"spec/en/guides.adoc", "spec/fr/compare.adoc", "spec/en/diagrams.adoc"} {
		if _, _, err := Route("writing", "/writing", src); err == nil || !strings.Contains(err.Error(), src) {
			t.Errorf("Route(%q): want an error naming the file, got %v", src, err)
		}
	}
}

// resolver routes targets the way Collect does, from the fixture's own files.
func resolver(t *testing.T) func(string) (string, bool) {
	t.Helper()
	return func(target string) (string, bool) {
		if strings.HasPrefix(target, "diagrams/") {
			return "/writing/" + target, true
		}
		if _, err := os.Stat(filepath.Join(fixture, target)); err != nil {
			return "", false
		}
		p, ok, err := Route("writing", "/writing", target)
		if err != nil || !ok {
			return "", false
		}
		return p.URL, true
	}
}

func rewrite(t *testing.T, from, body string) (string, []string) {
	t.Helper()
	out, problems := Rewrite([]byte(body), from, resolver(t))
	return string(out), problems
}

func TestRewriteSibling(t *testing.T) {
	if got, _ := rewrite(t, "spec/en/index.adoc", "See xref:keywords.adoc[Keywords].\n"); got != "See link:/writing/keywords/[Keywords].\n" {
		t.Errorf("en: %q", got)
	}
	if got, _ := rewrite(t, "spec/fr/index.adoc", "Voir xref:keywords.adoc[Mots clés].\n"); got != "Voir link:/fr/writing/keywords/[Mots clés].\n" {
		t.Errorf("fr: %q", got)
	}
}

func TestRewriteGlossaryFromGuide(t *testing.T) {
	in := ":abbr-api: xref:../../../../spec/fr/glossary.adoc#gl-api[{abbr-api-html}]\n"
	want := ":abbr-api: link:/fr/writing/glossary/#gl-api[{abbr-api-html}]\n"
	if got, p := rewrite(t, "docs/modules/fr/pages/_fpsot-terms.adoc", in); got != want || len(p) != 0 {
		t.Errorf("got %q, problems %v", got, p)
	}
}

func TestRewriteRegionBack(t *testing.T) {
	if got, _ := rewrite(t, "docs/modules/en/pages/jurisdictions/keywords/ca/index.adoc", "xref:../region-019.adoc[Americas]\n"); got != "link:/writing/compare/keywords/region-019/[Americas]\n" {
		t.Errorf("region: %q", got)
	}
	if got, _ := rewrite(t, "docs/modules/en/pages/jurisdictions/keywords/ca/qc.adoc", "xref:index.adoc[Canada]\n"); got != "link:/writing/compare/keywords/ca/[Canada]\n" {
		t.Errorf("country: %q", got)
	}
}

func TestRewriteKeepsInPage(t *testing.T) {
	in := "See xref:#WRT-011[WRT-011] and <<gl-api>>.\n"
	if got, p := rewrite(t, "spec/en/index.adoc", in); got != in || len(p) != 0 {
		t.Errorf("got %q, problems %v", got, p)
	}
}

func TestRewriteCrossReferenceForm(t *testing.T) {
	if got, _ := rewrite(t, "spec/en/index.adoc", "<<keywords.adoc#k,Keywords>>\n"); got != "link:/writing/keywords/#k[Keywords]\n" {
		t.Errorf("got %q", got)
	}
}

func TestRewriteSkipsListings(t *testing.T) {
	in := "----\nxref:missing.adoc[x]\n----\n"
	if got, p := rewrite(t, "spec/en/index.adoc", in); got != in || len(p) != 0 {
		t.Errorf("got %q, problems %v", got, p)
	}
}

func TestRewriteUnresolved(t *testing.T) {
	_, p := rewrite(t, "spec/en/index.adoc", "xref:missing.adoc[x]\n")
	if len(p) != 1 || !strings.Contains(p[0], "missing.adoc") || !strings.Contains(p[0], "spec/en/index.adoc") {
		t.Fatalf("problems %v", p)
	}
}

func TestRewriteImage(t *testing.T) {
	if got, _ := rewrite(t, "spec/en/keywords.adoc", "image::../../diagrams/x.svg[Drill-down]\n"); got != "image::/writing/diagrams/x.svg[Drill-down]\n" {
		t.Errorf("got %q", got)
	}
}

func collect(t *testing.T) string {
	t.Helper()
	out := t.TempDir()
	dates, err := LoadDates("testdata/dates.tsv")
	if err != nil {
		t.Fatal(err)
	}
	err = Collect(Options{Spec: "writing", Root: "/writing", SrcDir: fixture, OutDir: out, Version: "0.1.1",
		Dates: dates, DefaultDate: "2026-11-03", RepoURL: "https://github.com/fpsot-org/fpsot-spec-writing", SiteURL: "https://fpsot.org"})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func read(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestCollectHeader(t *testing.T) {
	out := collect(t)
	got := read(t, filepath.Join(out, "fr/writing/keywords/index.adoc"))
	want := []string{
		"= Keywords fr",
		":page-layout: spec",
		":page-link: /fr/writing/keywords/",
		":page-lang: fr",
		":page-spec: writing",
		":page-spec-title: Writing fr",
		":page-version: 0.1.1",
		":page-updated: 2026-10-02",
		":page-alternate: /writing/keywords/",
		":revnumber: 0.1.1",
		":contributing-url: https://github.com/fpsot-org/fpsot-spec-writing/blob/main/CONTRIBUTING.md",
		":spec-repo-url: https://github.com/fpsot-org/fpsot-spec-writing",
		":fpsot-site: https://fpsot.org",
		":toc-title: Table des matières",
	}
	lines := strings.Split(got, "\n")
	for i, w := range want {
		if i >= len(lines) || lines[i] != w {
			t.Fatalf("line %d: want %q\n--- got:\n%s", i+1, w, got)
		}
	}
	// Roq's AsciidoctorJ resolves includes only by absolute path, and ignores the
	// open range "2..-1" (2.2.0, checked on a test site): the range is explicit.
	if !strings.Contains(got, "include::"+filepath.ToSlash(filepath.Join(out, "_src/writing/spec/fr/keywords.adoc"))+"[lines=2..5]") {
		t.Fatalf("page does not include its body from _src:\n%s", got)
	}
	en := read(t, filepath.Join(out, "writing/index.adoc"))
	if !strings.Contains(en, ":page-updated: 2026-10-01\n") || strings.Contains(en, ":toc-title:") {
		t.Fatalf("English index header wrong:\n%s", en)
	}
	if !strings.Contains(read(t, filepath.Join(out, "writing/compare/keywords/fr/index.adoc")), ":page-lang: en\n") {
		t.Fatal("English France page is not lang en")
	}
	if !strings.Contains(en, ":page-updated: 2026-10-01\n") {
		t.Fatal("date from dates file not used")
	}
	if g := read(t, filepath.Join(out, "writing/guides/guide/index.adoc")); !strings.Contains(g, ":page-updated: 2026-11-03\n") {
		t.Fatalf("default date not used:\n%s", g)
	}
}

func TestCollectSourceMirror(t *testing.T) {
	out := collect(t)
	terms := read(t, filepath.Join(out, "_src/writing/docs/modules/fr/pages/_fpsot-terms.adoc"))
	if terms != ":abbr-api: link:/fr/writing/glossary/#gl-api[{abbr-api-html}]\n" {
		t.Fatalf("partial not rewritten: %q", terms)
	}
	book := read(t, filepath.Join(out, "_src/writing/spec/en/book.adoc"))
	if !strings.Contains(book, "include::index.adoc[leveloffset=+1]") {
		t.Fatalf("book includes changed:\n%s", book)
	}
	if _, err := os.Stat(filepath.Join(out, "public/writing/diagrams/x.svg")); err != nil {
		t.Fatal("diagram not copied")
	}
	if _, err := os.Stat(filepath.Join(out, "fr/writing/compare/keywords/ca/qc/index.adoc")); err != nil {
		t.Fatal("subdivision page missing")
	}
}

func TestCollectNoAlternate(t *testing.T) {
	src := t.TempDir()
	os.MkdirAll(filepath.Join(src, "spec/en"), 0o755)
	os.WriteFile(filepath.Join(src, "spec/en/index.adoc"), []byte("= Only English\n\nText.\n"), 0o644)
	out := t.TempDir()
	if err := Collect(Options{Spec: "x", Root: "/x", SrcDir: src, OutDir: out, Version: "0.1.0", DefaultDate: "2026-11-03", RepoURL: "https://github.com/fpsot-org/fpsot-spec-x", SiteURL: "https://fpsot.org"}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(read(t, filepath.Join(out, "x/index.adoc")), ":page-alternate:") {
		t.Fatal("alternate written for a page with no French twin")
	}
}

func TestCollectCollision(t *testing.T) {
	out := t.TempDir()
	opt := Options{Spec: "writing", Root: "/writing", SrcDir: fixture, OutDir: out, Version: "0.1.1", DefaultDate: "2026-11-03", RepoURL: "https://github.com/fpsot-org/fpsot-spec-writing", SiteURL: "https://fpsot.org"}
	opt.route = func(spec, root, src string) (Page, bool, error) {
		p, ok, err := Route(spec, root, src)
		if src == "spec/en/glossary.adoc" {
			p.URL = "/writing/keywords/"
		}
		return p, ok, err
	}
	err := Collect(opt)
	if err == nil || !strings.Contains(err.Error(), "spec/en/glossary.adoc") || !strings.Contains(err.Error(), "spec/en/keywords.adoc") {
		t.Fatalf("want a collision error naming both files, got %v", err)
	}
}

func TestCollectUnresolvedFails(t *testing.T) {
	src := t.TempDir()
	os.MkdirAll(filepath.Join(src, "spec/en"), 0o755)
	os.WriteFile(filepath.Join(src, "spec/en/index.adoc"), []byte("= T\n\nxref:nope.adoc[x]\n"), 0o644)
	err := Collect(Options{Spec: "x", Root: "/x", SrcDir: src, OutDir: t.TempDir(), Version: "0.1.0", DefaultDate: "2026-11-03", RepoURL: "u", SiteURL: "s"})
	if err == nil || !strings.Contains(err.Error(), "nope.adoc") {
		t.Fatalf("want unresolved error, got %v", err)
	}
}

// Header attributes of the source, such as :toc: in a book, stay in the page header:
// in the body they would not take effect.
func TestCollectKeepsHeaderAttributes(t *testing.T) {
	out := collect(t)
	book := read(t, filepath.Join(out, "writing/book/index.adoc"))
	head, _, _ := strings.Cut(book, "\ninclude::")
	for _, want := range []string{"\n:doctype: book\n", "\n:toc:\n"} {
		if !strings.Contains(head+"\n", want) {
			t.Errorf("book page header lacks %q:\n%s", strings.TrimSpace(want), head)
		}
	}
	if !strings.HasPrefix(book, "= Book en\n:page-layout: spec\n") {
		t.Errorf("title and site header must come first:\n%s", head)
	}
}

// With the release PDFs, each page links its own language's PDF and the other one,
// with their sizes in bytes, and the PDFs go next to the pages, one per language.
func TestCollectPDFs(t *testing.T) {
	pdfs := t.TempDir()
	en := filepath.Join(pdfs, "fpsot-spec-writing-en.pdf")
	fr := filepath.Join(pdfs, "fpsot-spec-writing-fr.pdf")
	os.WriteFile(en, []byte(strings.Repeat("e", 1234)), 0o644)
	os.WriteFile(fr, []byte(strings.Repeat("f", 2345)), 0o644)
	out := t.TempDir()
	pub := filepath.Join(out, "pub")
	err := Collect(Options{Spec: "writing", Root: "/writing", SrcDir: fixture, OutDir: out, PublicDir: pub, Version: "0.1.1",
		DefaultDate: "2026-11-03", RepoURL: "https://github.com/fpsot-org/fpsot-spec-writing", SiteURL: "https://fpsot.org",
		PDFs: map[string]string{"en": en, "fr": fr}})
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"writing/fpsot-spec-writing-en.pdf", "fr/writing/fpsot-spec-writing-fr.pdf"} {
		if _, err := os.Stat(filepath.Join(pub, f)); err != nil {
			t.Errorf("%s not copied", f)
		}
	}
	for page, want := range map[string][]string{
		"fr/writing/keywords/index.adoc": {":page-pdf: /fr/writing/fpsot-spec-writing-fr.pdf\n", ":page-pdf-bytes: 2345\n",
			":page-pdf-other: /writing/fpsot-spec-writing-en.pdf\n", ":page-pdf-other-bytes: 1234\n"},
		"writing/guides/guide/index.adoc": {":page-pdf: /writing/fpsot-spec-writing-en.pdf\n", ":page-pdf-bytes: 1234\n",
			":page-pdf-other: /fr/writing/fpsot-spec-writing-fr.pdf\n", ":page-pdf-other-bytes: 2345\n"},
	} {
		got := read(t, filepath.Join(out, page))
		head, _, _ := strings.Cut(got, "\ninclude::")
		for _, w := range want {
			if !strings.Contains(head+"\n", w) {
				t.Errorf("%s lacks %q:\n%s", page, strings.TrimSpace(w), head)
			}
		}
	}
	// Without PDFs, no page names one.
	if strings.Contains(read(t, filepath.Join(collect(t), "writing/index.adoc")), ":page-pdf") {
		t.Error("page-pdf written without PDFs")
	}
	// A PDF that does not exist fails, naming it.
	err = Collect(Options{Spec: "writing", Root: "/writing", SrcDir: fixture, OutDir: t.TempDir(), Version: "0.1.1",
		DefaultDate: "2026-11-03", RepoURL: "u", SiteURL: "s", PDFs: map[string]string{"en": en, "fr": filepath.Join(pdfs, "nope.pdf")}})
	if err == nil || !strings.Contains(err.Error(), "nope.pdf") {
		t.Fatalf("want an error naming the missing PDF, got %v", err)
	}
}

// With the legal data of the spec, each page names its copyright and licenses, in its language.
func TestCollectLegal(t *testing.T) {
	legal := filepath.Join(t.TempDir(), "legal.json")
	os.WriteFile(legal, []byte(`{"en": {"copyright": "Copyright 2026 The FPSOT Authors", "license": "Community Specification License 1.0",
  "license-url": "https://github.com/CommunitySpecification/1.0", "code": "Apache License 2.0", "code-url": "https://www.apache.org/licenses/LICENSE-2.0"},
 "fr": {"copyright": "© 2026 Les auteurs de la FPSOT", "license": "licence Community Specification 1.0",
  "license-url": "https://github.com/CommunitySpecification/1.0", "code": "", "code-url": ""}}`), 0o644)
	out := t.TempDir()
	err := Collect(Options{Spec: "writing", Root: "/writing", SrcDir: fixture, OutDir: out, Version: "0.1.1",
		DefaultDate: "2026-11-03", RepoURL: "https://github.com/fpsot-org/fpsot-spec-writing", SiteURL: "https://fpsot.org", Legal: legal})
	if err != nil {
		t.Fatal(err)
	}
	en := read(t, filepath.Join(out, "writing/guides/guide/index.adoc"))
	for _, w := range []string{":page-copyright: Copyright 2026 The FPSOT Authors\n", ":page-license: Community Specification License 1.0\n",
		":page-license-url: https://github.com/CommunitySpecification/1.0\n", ":page-code-license: Apache License 2.0\n",
		":page-code-license-url: https://www.apache.org/licenses/LICENSE-2.0\n"} {
		if !strings.Contains(en, w) {
			t.Errorf("English page lacks %q", strings.TrimSpace(w))
		}
	}
	fr := read(t, filepath.Join(out, "fr/writing/index.adoc"))
	if !strings.Contains(fr, ":page-copyright: © 2026 Les auteurs de la FPSOT\n") || strings.Contains(fr, ":page-code-license") {
		t.Errorf("French page header wrong:\n%s", fr)
	}
	err = Collect(Options{Spec: "writing", Root: "/writing", SrcDir: fixture, OutDir: t.TempDir(), Version: "0.1.1",
		DefaultDate: "2026-11-03", RepoURL: "u", SiteURL: "s", Legal: filepath.Join(t.TempDir(), "nope.json")})
	if err == nil || !strings.Contains(err.Error(), "nope.json") {
		t.Fatalf("want an error naming the missing legal file, got %v", err)
	}
}
