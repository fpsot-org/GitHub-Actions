// SPDX-License-Identifier: Apache-2.0
package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNoFrenchDir(t *testing.T) {
	d := t.TempDir()
	if err := os.MkdirAll(filepath.Join(d, "en"), 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(d, "en", "a.adoc"), []byte("A"), 0o644)
	var out bytes.Buffer
	if code := run([]string{"-strict", d}, &out, &out); code != 1 || !strings.Contains(out.String(), "fr/ missing") {
		t.Fatalf("code %d, out %q", code, out.String())
	}
	out.Reset()
	if code := run([]string{d}, &out, &out); code != 0 || !strings.Contains(out.String(), "warning:") {
		t.Fatalf("non-strict: code %d, out %q", code, out.String())
	}
}
