// SPDX-License-Identifier: Apache-2.0

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCLI(t *testing.T) {
	out := t.TempDir()
	var stdout, stderr bytes.Buffer
	args := []string{"-spec", "writing", "-src", "../../internal/site/testdata/spec", "-out", out, "-public", filepath.Join(out, "pub"),
		"-version", "0.1.1", "-dates", "../../internal/site/testdata/dates.tsv", "-default-date", "2026-11-03",
		"-repo-url", "https://github.com/fpsot-org/fpsot-spec-writing"}
	if code := run(args, &stdout, &stderr); code != 0 {
		t.Fatalf("exit %d: %s", code, stderr.String())
	}
	if _, err := os.Stat(filepath.Join(out, "pub/writing/diagrams/x.svg")); err != nil {
		t.Fatal("diagram not copied")
	}
	if _, err := os.Stat(filepath.Join(out, "fr/writing/index.adoc")); err != nil {
		t.Fatal("French index missing")
	}

	bad := t.TempDir()
	os.MkdirAll(filepath.Join(bad, "spec/en"), 0o755)
	os.WriteFile(filepath.Join(bad, "spec/en/index.adoc"), []byte("= T\n\nxref:nope.adoc[x]\n"), 0o644)
	stderr.Reset()
	args = []string{"-spec", "x", "-src", bad, "-out", t.TempDir(), "-version", "0.1.0", "-default-date", "2026-11-03", "-repo-url", "https://github.com/fpsot-org/fpsot-spec-x"}
	if code := run(args, &stdout, &stderr); code != 1 || !strings.Contains(stderr.String(), "spec/en/index.adoc") {
		t.Fatalf("exit %d, stderr %q", code, stderr.String())
	}

	stderr.Reset()
	if code := run([]string{"-spec", "x"}, &stdout, &stderr); code != 2 {
		t.Fatalf("missing flags: exit %d", code)
	}
}
