// SPDX-License-Identifier: Apache-2.0

package termbase

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func load(t *testing.T) *Base {
	t.Helper()
	b, err := Load("testdata/terms.yaml")
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func writeTemp(t *testing.T, name, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

const goodEntry = `  - id: ok
    kind: abbreviation
    en: {short: OK, full: okay, definition: Fine.}
    fr: {short: OK, full: d'accord, definition: Bien.}
`

func TestLoadRejects(t *testing.T) {
	cases := map[string]struct{ yaml, want string }{
		"duplicate":                  {"terms:\n" + goodEntry + goodEntry, `"ok"`},
		"upper-case id":              {"terms:\n" + strings.Replace(goodEntry, "id: ok", "id: API", 1), `"API"`},
		"unknown kind":               {"terms:\n" + strings.Replace(goodEntry, "kind: abbreviation", "kind: acronym", 1), `"ok"`},
		"missing fr definition":      {"terms:\n" + strings.Replace(goodEntry, ", definition: Bien.", "", 1), `"ok"`},
		"abbreviation without short": {"terms:\n" + strings.Replace(goodEntry, "{short: OK, full: okay", "{full: okay", 1), `"ok"`},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := Load(writeTemp(t, "terms.yaml", c.yaml))
			if err == nil {
				t.Fatal("want error, got nil")
			}
			if !strings.Contains(err.Error(), c.want) {
				t.Fatalf("error %q does not name %s", err, c.want)
			}
		})
	}
}

func TestAttributesShape(t *testing.T) {
	got := load(t).Attributes("en", "glossary.adoc")
	want := `ifdef::backend-html5[]
:abbr-api-html: pass:[<abbr title="application programming interface">API</abbr>]
:abbr-api: xref:glossary.adoc#gl-api[{abbr-api-html}]
endif::[]
ifndef::backend-html5[]
:abbr-api: xref:glossary.adoc#gl-api[API]
endif::[]
:abbr-api-first: application programming interface ({abbr-api})
`
	if !strings.Contains(got, want) {
		t.Fatalf("attributes do not contain the api block:\n%s", got)
	}
	if !strings.Contains(got, ":term-registry: xref:glossary.adoc#gl-registry[registry]\n") {
		t.Fatalf("attributes do not contain term-registry:\n%s", got)
	}
	fr := load(t).Attributes("fr", "glossary.adoc")
	if !strings.Contains(fr, `title="interface de programmation d'application"`) {
		t.Fatalf("French attributes do not use the French full form:\n%s", fr)
	}
}

func TestAttributesEscape(t *testing.T) {
	yaml := `terms:
  - id: rd
    kind: abbreviation
    en: {short: "R]D", full: "R&D \"pilot\" <beta> [x] l'outil", definition: Test.}
    fr: {short: "R]D", full: "R&D", definition: Test.}
`
	b, err := Load(writeTemp(t, "terms.yaml", yaml))
	if err != nil {
		t.Fatal(err)
	}
	got := b.Attributes("en", "glossary.adoc")
	if !strings.Contains(got, `title="R&amp;D &quot;pilot&quot; &lt;beta&gt; [x\] l'outil"`) {
		t.Fatalf("title not escaped:\n%s", got)
	}
	if !strings.Contains(got, `>R\]D</abbr>]`) || !strings.Contains(got, `#gl-rd[R\]D]`) {
		t.Fatalf("] not escaped in xref text:\n%s", got)
	}
}

func TestUsedAndGlossary(t *testing.T) {
	b := load(t)
	used, err := Used([]string{"testdata/pages/good.adoc"})
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"api", "registry", "screen", "file"} {
		if !used[id] {
			t.Errorf("%s not reported as used", id)
		}
	}
	if used["pdf"] {
		t.Error("pdf reported as used")
	}
	en := b.Glossary("en", used)
	if !strings.HasPrefix(en, "= Glossary\n") {
		t.Fatalf("English glossary title wrong:\n%s", en)
	}
	if !strings.Contains(en, "[[gl-api]]API (application programming interface):: Rules that let one program use another.\n") {
		t.Fatalf("api entry missing:\n%s", en)
	}
	if !strings.Contains(en, "[[gl-registry]]registry:: A system that records who holds what.\n") {
		t.Fatalf("registry entry missing:\n%s", en)
	}
	if strings.Contains(en, "gl-pdf") {
		t.Fatal("unused pdf in glossary")
	}
	fr := b.Glossary("fr", used)
	if !strings.HasPrefix(fr, "= Glossaire\n") {
		t.Fatalf("French glossary title wrong:\n%s", fr)
	}
	if e, f := strings.Index(fr, "[[gl-screen]]écran"), strings.Index(fr, "[[gl-file]]fichier"); e < 0 || f < 0 || e > f {
		t.Fatalf("écran must sort before fichier:\n%s", fr)
	}
}

func TestGlossaryEmpty(t *testing.T) {
	b := load(t)
	if g := b.Glossary("en", map[string]bool{}); !strings.Contains(g, "This specification uses no defined terms.") {
		t.Fatalf("empty English glossary:\n%s", g)
	}
	if g := b.Glossary("fr", nil); !strings.Contains(g, "Cette spécification n'utilise aucun terme défini.") {
		t.Fatalf("empty French glossary:\n%s", g)
	}
}

func TestCheckFirstUse(t *testing.T) {
	b := load(t)
	f := b.Check([]string{"testdata/pages/bad-order.adoc"})
	if len(f) != 1 || f[0].Line != 3 || !strings.Contains(f[0].Msg, "{abbr-api}") {
		t.Fatalf("want one finding at line 3, got %+v", f)
	}
	if f := b.Check([]string{"testdata/pages/good.adoc"}); len(f) != 0 {
		t.Fatalf("good page has findings: %+v", f)
	}
	p := writeTemp(t, "unknown.adoc", "= T\n\nThe {abbr-nope-first} and {term-api}.\n")
	f = b.Check([]string{p})
	if len(f) != 2 || !strings.Contains(f[0].Msg, `unknown term "nope"`) || !strings.Contains(f[1].Msg, `"api" is an abbreviation`) {
		t.Fatalf("unknown and wrong-kind references not reported: %+v", f)
	}
}

func TestCheckSkipsListings(t *testing.T) {
	b := load(t)
	if f := b.Check([]string{"testdata/pages/listing.adoc"}); len(f) != 0 {
		t.Fatalf("listing and inline code produced findings: %+v", f)
	}
	used, err := Used([]string{"testdata/pages/listing.adoc"})
	if err != nil {
		t.Fatal(err)
	}
	if len(used) != 0 {
		t.Fatalf("listing and inline code counted as uses: %v", used)
	}
}

func TestFindingString(t *testing.T) {
	if s := (Finding{"a.adoc", 3, "msg"}).String(); s != "a.adoc:3: msg" {
		t.Fatal(s)
	}
}

// Asciidoctor substitutes attributes inside plain backticks, so those count.
func TestCheckCountsPlainBackticks(t *testing.T) {
	b := load(t)
	p := writeTemp(t, "code.adoc", "= T\n\nThe call `{abbr-api}` is short.\n")
	if f := b.Check([]string{p}); len(f) != 1 || !strings.Contains(f[0].Msg, "{abbr-api} used before") {
		t.Fatalf("want a first-use finding for `{abbr-api}`, got %+v", f)
	}
}

// A full form that already holds the abbreviation, such as "document RFC", must not
// repeat it in brackets: the first use marks the abbreviation inside the full form.
func TestAttributesFullFormHoldsShort(t *testing.T) {
	yaml := `terms:
  - id: rfc
    kind: abbreviation
    en: {short: RFC, full: Request for Comments, definition: Test.}
    fr: {short: RFC, full: document RFC, definition: Test.}
`
	b, err := Load(writeTemp(t, "terms.yaml", yaml))
	if err != nil {
		t.Fatal(err)
	}
	if fr := b.Attributes("fr", "glossary.adoc"); !strings.Contains(fr, ":abbr-rfc-first: document {abbr-rfc}\n") {
		t.Fatalf("French first form repeats the abbreviation:\n%s", fr)
	}
	if en := b.Attributes("en", "glossary.adoc"); !strings.Contains(en, ":abbr-rfc-first: Request for Comments ({abbr-rfc})\n") {
		t.Fatalf("English first form changed:\n%s", en)
	}
}

// The abbreviation is found as a whole word even when it ends in a symbol, and not
// inside a longer word.
func TestFirstFormWordBoundaries(t *testing.T) {
	cases := []struct{ short, full, want string }{
		{"C++", "langage C++", "langage {abbr-x}"},
		{"C++", "C++ language", "{abbr-x} language"},
		{"SVG", "SVGZ file", "SVGZ file ({abbr-x})"},
		{"URL", "adresse URL", "adresse {abbr-x}"},
	}
	for _, c := range cases {
		if got := firstForm("x", Form{Short: c.short, Full: c.full}); got != c.want {
			t.Errorf("firstForm(%q, %q) = %q, want %q", c.short, c.full, got, c.want)
		}
	}
}
