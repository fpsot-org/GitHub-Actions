// SPDX-License-Identifier: Apache-2.0

package jurisdiction

import (
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var update = flag.Bool("update", false, "rewrite golden files")

var today = time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC)

func baseline(t *testing.T) *Baseline {
	t.Helper()
	b, err := LoadBaseline("testdata/valid/baseline.yaml")
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// copyValid copies the valid fixture to a temp dir and applies edits (path → content; "" deletes).
func copyValid(t *testing.T, edits map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for _, p := range []string{"baseline.yaml", "ca.yaml", "ca/qc.yaml"} {
		data, err := os.ReadFile(filepath.Join("testdata/valid", p))
		if err != nil {
			t.Fatal(err)
		}
		os.MkdirAll(filepath.Dir(filepath.Join(dir, p)), 0o755)
		os.WriteFile(filepath.Join(dir, p), data, 0o644)
	}
	for p, body := range edits {
		full := filepath.Join(dir, p)
		if body == "" {
			os.Remove(full)
			continue
		}
		os.MkdirAll(filepath.Dir(full), 0o755)
		os.WriteFile(full, []byte(body), 0o644)
	}
	return dir
}

func read(t *testing.T, p string) string {
	t.Helper()
	data, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestTerritories(t *testing.T) {
	tr := Territories()
	cs := tr.Continents()
	if len(cs) != 5 || cs[0].Code != "002" || cs[1].Code != "019" || cs[4].Code != "009" {
		t.Fatalf("continents: %+v", cs)
	}
	has := func(r Region, c string) bool {
		for _, x := range r.Countries {
			if x == c {
				return true
			}
		}
		return false
	}
	if !has(cs[1], "CA") || !has(cs[1], "US") || !has(cs[3], "FR") {
		t.Fatal("CA, US or FR missing from its continent")
	}
	total := 0
	for _, r := range cs {
		if has(r, "EU") {
			t.Fatalf("%s contains EU", r.Code)
		}
		total += len(r.Countries)
	}
	if total < 240 {
		t.Fatalf("only %d countries", total)
	}
	if n := tr.CountryName("CA", "fr"); n != "Canada" {
		t.Fatalf("CountryName(CA, fr) = %q", n)
	}
	if n := tr.CountryName("US", "fr"); n != "États-Unis" {
		t.Fatalf("CountryName(US, fr) = %q", n)
	}
	if c := tr.ContinentOf("CA"); c != "019" {
		t.Fatalf("ContinentOf(CA) = %q", c)
	}
}

func TestLoadDirValid(t *testing.T) {
	files, err := LoadDir("testdata/valid", baseline(t), LoadOptions{Today: today})
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 2 || files[0].Code != "CA" || files[1].Code != "CA-QC" {
		t.Fatalf("files: %+v", files)
	}
}

func TestPathCodeMismatch(t *testing.T) {
	for name, code := range map[string]string{"other subdivision": "CA-ON", "lower case": "ca-qc"} {
		t.Run(name, func(t *testing.T) {
			body := strings.Replace(read(t, "testdata/valid/ca/qc.yaml"), "code: CA-QC", "code: "+code, 1)
			dir := copyValid(t, map[string]string{"ca/qc.yaml": body})
			_, err := LoadDir(dir, baseline(t), LoadOptions{Today: today})
			if err == nil || !strings.Contains(err.Error(), filepath.Join("ca", "qc.yaml")) {
				t.Fatalf("want error naming ca/qc.yaml, got %v", err)
			}
		})
	}
}

func TestRejects(t *testing.T) {
	ca := read(t, "testdata/valid/ca.yaml")
	cases := map[string]string{
		"unknown row ID":  strings.Replace(ca, "id: WRT-001", "id: WRT-999", 1),
		"unknown status":  strings.Replace(ca, "status: same", "status: partial", 1),
		"missing fr text": strings.Replace(ca, ", fr: Langage clair pour le contenu Web.", "", 1),
		"missing archive": strings.Replace(ca, `, archive: "https://web.archive.org/web/2026/https://www.canada.ca/"`, "", 1),
		"unknown country": strings.Replace(ca, "code: CA", "code: ZZ", 1),
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			edits := map[string]string{"ca.yaml": body}
			if name == "unknown country" {
				edits = map[string]string{"ca.yaml": "", "zz.yaml": body}
			}
			dir := copyValid(t, edits)
			if _, err := LoadDir(dir, baseline(t), LoadOptions{Today: today}); err == nil {
				t.Fatal("want error, got nil")
			}
		})
	}
}

func TestStaleBoundary(t *testing.T) {
	files, err := LoadDir("testdata/valid", baseline(t), LoadOptions{Today: today})
	if err != nil {
		t.Fatal(err)
	}
	stale := Stale(files, today, 12)
	if len(stale) != 1 || stale[0].ID != "WRT-010" || !strings.HasSuffix(stale[0].Path, filepath.Join("ca", "qc.yaml")) {
		t.Fatalf("want only WRT-010 in ca/qc.yaml (2025-11-01) stale, got %+v", stale)
	}
}

func TestFutureDate(t *testing.T) {
	body := strings.Replace(read(t, "testdata/valid/ca.yaml"), "last_checked: \"2026-10-01\"", "last_checked: \"2026-11-03\"", 1)
	dir := copyValid(t, map[string]string{"ca.yaml": body})
	_, err := LoadDir(dir, baseline(t), LoadOptions{Today: today})
	if err == nil || !strings.Contains(err.Error(), "future") {
		t.Fatalf("want future-date error, got %v", err)
	}
}

func TestGenerate(t *testing.T) {
	b := baseline(t)
	files, err := LoadDir("testdata/valid", b, LoadOptions{Today: today})
	if err != nil {
		t.Fatal(err)
	}
	for _, lang := range []string{"en", "fr"} {
		out := t.TempDir()
		if err := Generate(b, files, Territories(), lang, out); err != nil {
			t.Fatal(err)
		}
		for _, p := range []string{"plain-language/index.adoc", "plain-language/region-019.adoc", "plain-language/ca/index.adoc", "plain-language/ca/qc.adoc", "keywords/ca/qc.adoc", "plain-language/fr/index.adoc"} {
			got := read(t, filepath.Join(out, p))
			golden := filepath.Join("testdata/golden", lang, p)
			if *update {
				os.MkdirAll(filepath.Dir(golden), 0o755)
				os.WriteFile(golden, []byte(got), 0o644)
				continue
			}
			if want := read(t, golden); got != want {
				t.Errorf("%s/%s differs from golden:\n%s", lang, p, got)
			}
		}
		stub := read(t, filepath.Join(out, "plain-language/fr/index.adoc"))
		for _, want := range []string{":page-type: reference", map[string]string{"en": "It is not legal advice.", "fr": "Elle ne constitue pas un avis juridique."}[lang], "link:{contributing-url}["} {
			if !strings.Contains(stub, want) {
				t.Errorf("%s France stub lacks %q", lang, want)
			}
		}
		if _, err := os.Stat(filepath.Join(out, "plain-language/qc.adoc")); err == nil {
			t.Error("subdivision page written outside its country")
		}
	}
}

func TestCellEscapesPipes(t *testing.T) {
	b := baseline(t)
	out := t.TempDir()
	if err := Generate(b, nil, Territories(), "en", out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(read(t, filepath.Join(out, "plain-language/index.adoc")), `20 words or fewer \| active voice`) {
		t.Fatal("pipe in cell not escaped")
	}
}
