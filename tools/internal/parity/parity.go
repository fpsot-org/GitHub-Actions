// SPDX-License-Identifier: Apache-2.0

// Package parity compares the English and French page sets of a spec folder.
package parity

import (
	"bufio"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// PendingMarker is the attribute line that marks a French page as not yet translated.
const PendingMarker = ":translation-status: pending"

// Report lists relative .adoc paths that break parity.
type Report struct {
	MissingFR []string // in en/ but not fr/
	MissingEN []string // in fr/ but not en/
	PendingFR []string // in fr/ but marked as not yet translated
}

// Compare checks root/en against root/fr. A missing fr/ folder is returned as an
// *fs.PathError so callers can report it.
func Compare(root string) (Report, error) {
	var r Report
	en, err := pages(filepath.Join(root, "en"))
	if err != nil {
		return r, err
	}
	fr, err := pages(filepath.Join(root, "fr"))
	if err != nil {
		return r, err
	}
	for p := range en {
		if !fr[p] {
			r.MissingFR = append(r.MissingFR, p)
		}
	}
	for p := range fr {
		if !en[p] {
			r.MissingEN = append(r.MissingEN, p)
		}
		pending, err := isPending(filepath.Join(root, "fr", p))
		if err != nil {
			return r, err
		}
		if pending {
			r.PendingFR = append(r.PendingFR, p)
		}
	}
	sort.Strings(r.MissingFR)
	sort.Strings(r.MissingEN)
	sort.Strings(r.PendingFR)
	return r, nil
}

func pages(dir string) (map[string]bool, error) {
	out := map[string]bool{}
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".adoc") {
			return err
		}
		rel, err := filepath.Rel(dir, path)
		out[filepath.ToSlash(rel)] = true
		return err
	})
	return out, err
}

func isPending(path string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimPrefix(strings.TrimRight(s.Text(), "\r"), "\ufeff")
		if strings.TrimSpace(line) == PendingMarker {
			return true, nil
		}
	}
	return false, s.Err()
}
