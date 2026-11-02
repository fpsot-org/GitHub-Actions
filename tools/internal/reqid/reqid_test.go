// SPDX-License-Identifier: Apache-2.0
package reqid

import (
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, dir, name, content string) {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDefinedFindsAnchors(t *testing.T) {
	d := t.TempDir()
	write(t, d, "a.adoc", "= Title\n\n[[VCS-001]]\nCommits MUST be signed.\n\n[[VCS-002]]\nText.\n")
	got, err := Defined(d)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got["VCS-001"] == nil || got["VCS-002"] == nil {
		t.Fatalf("got %v", got)
	}
	if got["VCS-001"][0].Line != 3 {
		t.Fatalf("line = %d, want 3", got["VCS-001"][0].Line)
	}
}

func TestIgnoresAnchorsInListings(t *testing.T) {
	d := t.TempDir()
	write(t, d, "a.adoc", "----\n[[ABC-001]]\n----\n....\n[[ABC-002]]\n....\n////\n[[ABC-003]]\n////\n")
	got, err := Defined(d)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("got %v, want none", got)
	}
}

func TestCRLFAndBOM(t *testing.T) {
	d := t.TempDir()
	write(t, d, "a.adoc", "\ufeff[[VCS-001]]\r\nText.\r\n")
	got, err := Defined(d)
	if err != nil {
		t.Fatal(err)
	}
	if locs := got["VCS-001"]; len(locs) != 1 || locs[0].Line != 1 {
		t.Fatalf("got %v", got)
	}
}

func TestDuplicateReported(t *testing.T) {
	d := t.TempDir()
	write(t, d, "a.adoc", "[[VCS-003]]\nA.\n")
	write(t, d, "sub/b.adoc", "[[VCS-003]]\nB.\n")
	got, err := Defined(d)
	if err != nil {
		t.Fatal(err)
	}
	if len(got["VCS-003"]) != 2 {
		t.Fatalf("got %v", got)
	}
}

func TestCitedUsesPrefixOnly(t *testing.T) {
	d := t.TempDir()
	write(t, d, "SKILL.md", "Use ISO-639 and VCS-004.\n")
	got, err := Cited([]string{d}, "VCS")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got["VCS-004"] == nil {
		t.Fatalf("got %v", got)
	}
}
