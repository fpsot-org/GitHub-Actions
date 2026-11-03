// SPDX-License-Identifier: Apache-2.0

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const valid = "../../internal/jurisdiction/testdata/valid"

func TestStrictExit(t *testing.T) {
	for _, strict := range []bool{false, true} {
		var out, errb bytes.Buffer
		args := []string{"-dir", valid, "-lang", "en", "-out", t.TempDir(), "-today", "2026-11-02"}
		if strict {
			args = append(args, "-strict")
		}
		code := run(args, &out, &errb)
		want := map[bool]int{false: 0, true: 1}[strict]
		if code != want {
			t.Fatalf("strict=%v: exit %d, want %d (stderr %q)", strict, code, want, errb.String())
		}
		if !strings.Contains(out.String(), "::warning file=") || !strings.Contains(out.String(), "WRT-010 last checked 2025-11-01") {
			t.Fatalf("strict=%v: warning missing: %q", strict, out.String())
		}
	}
}

func TestWritesPages(t *testing.T) {
	dir := t.TempDir()
	var out, errb bytes.Buffer
	if code := run([]string{"-dir", valid, "-lang", "fr", "-out", dir, "-today", "2026-11-02"}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if _, err := os.Stat(filepath.Join(dir, "plain-language", "ca", "qc.adoc")); err != nil {
		t.Fatal(err)
	}
}

func TestLoadErrorExits1(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "baseline.yaml"), []byte("topics: {}\nrows: []\n"), 0o644)
	os.WriteFile(filepath.Join(dir, "ca.yaml"), []byte("code: CA\nname: {en: Canada, fr: Canada}\nrows:\n  - id: WRT-001\n"), 0o644)
	var out, errb bytes.Buffer
	if code := run([]string{"-dir", dir, "-lang", "en", "-out", t.TempDir()}, &out, &errb); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
}

func TestBadArguments(t *testing.T) {
	var out, errb bytes.Buffer
	if code := run([]string{"-dir", valid, "-lang", "de", "-out", "x"}, &out, &errb); code != 2 {
		t.Fatalf("exit %d", code)
	}
	if code := run([]string{"-dir", valid, "-lang", "en", "-out", "x", "-today", "02/11/2026"}, &out, &errb); code != 2 {
		t.Fatalf("bad date: exit %d", code)
	}
}
