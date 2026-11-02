// SPDX-License-Identifier: Apache-2.0
package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T, files map[string]string) string {
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

func runIn(t *testing.T, dir string, args ...string) (int, string) {
	t.Helper()
	wd, _ := os.Getwd()
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(wd)
	var out, errb bytes.Buffer
	code := run(args, &out, &errb)
	return code, out.String() + errb.String()
}

func TestCLIStrictMismatch(t *testing.T) {
	d := fixture(t, map[string]string{
		"spec/en/a.adoc": "[[VCS-001]]\nA.\n\n[[VCS-002]]\nB.\n",
		"spec/fr/a.adoc": "[[VCS-001]]\nA.\n",
		"skill/SKILL.md": "See VCS-001.\n",
	})
	if code, out := runIn(t, d, "-prefix", "VCS", "-spec", "spec", "-cite", "skill,rules"); code != 0 || !strings.Contains(out, "warning:") {
		t.Fatalf("non-strict: code %d, out %q", code, out)
	}
	if code, out := runIn(t, d, "-prefix", "VCS", "-spec", "spec", "-cite", "skill,rules", "-strict"); code != 1 || !strings.Contains(out, "VCS-002") {
		t.Fatalf("strict: code %d, out %q", code, out)
	}
}

func TestCLIUnknownCitationFails(t *testing.T) {
	d := fixture(t, map[string]string{
		"spec/en/a.adoc": "[[VCS-001]]\nA.\n",
		"spec/fr/a.adoc": "[[VCS-001]]\nA.\n",
		"skill/SKILL.md": "See VCS-099.\n",
	})
	if code, out := runIn(t, d, "-prefix", "VCS", "-spec", "spec", "-cite", "skill"); code != 1 || !strings.Contains(out, "VCS-099") {
		t.Fatalf("code %d, out %q", code, out)
	}
}

func TestCLIDuplicateFails(t *testing.T) {
	d := fixture(t, map[string]string{
		"spec/en/a.adoc": "[[VCS-001]]\nA.\n\n[[VCS-001]]\nB.\n",
		"spec/fr/a.adoc": "[[VCS-001]]\nA.\n",
	})
	if code, out := runIn(t, d, "-prefix", "VCS", "-spec", "spec"); code != 1 || !strings.Contains(out, "duplicate") {
		t.Fatalf("code %d, out %q", code, out)
	}
}
