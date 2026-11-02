// SPDX-License-Identifier: Apache-2.0
package parity

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func tree(t *testing.T, files map[string]string) string {
	t.Helper()
	d := t.TempDir()
	for name, content := range files {
		p := filepath.Join(d, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return d
}

func TestMissingFR(t *testing.T) {
	d := tree(t, map[string]string{"en/a.adoc": "A", "en/b.adoc": "B", "fr/a.adoc": "A"})
	r, err := Compare(d)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(r.MissingFR, []string{"b.adoc"}) || len(r.MissingEN) != 0 {
		t.Fatalf("got %+v", r)
	}
}

func TestPendingCounted(t *testing.T) {
	d := tree(t, map[string]string{"en/a.adoc": "A", "fr/a.adoc": "= A\n:translation-status: pending\n"})
	r, err := Compare(d)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(r.PendingFR, []string{"a.adoc"}) {
		t.Fatalf("got %+v", r)
	}
}

func TestBOMPageCountsAsTranslated(t *testing.T) {
	d := tree(t, map[string]string{"en/a.adoc": "A", "fr/a.adoc": "\ufeff= A\r\nTexte.\r\n"})
	r, err := Compare(d)
	if err != nil {
		t.Fatal(err)
	}
	if len(r.PendingFR) != 0 || len(r.MissingFR) != 0 {
		t.Fatalf("got %+v", r)
	}
}
