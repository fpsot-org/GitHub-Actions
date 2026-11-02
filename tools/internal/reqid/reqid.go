// SPDX-License-Identifier: Apache-2.0

// Package reqid finds requirement IDs defined in AsciiDoc spec text and IDs cited elsewhere.
//
// A requirement is defined by an anchor line such as [[VCS-001]] placed directly above
// its paragraph. Anchors inside listing, literal and comment blocks are examples, not
// definitions, and are ignored.
package reqid

import (
	"bufio"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Location is where an ID appears.
type Location struct {
	File string
	Line int
}

var anchor = regexp.MustCompile(`^\[\[([A-Z]{3}-\d{3})\]\]\s*$`)

// Delimiters of blocks whose content is not normative text.
var delimiters = map[string]bool{"----": true, "....": true, "////": true}

// Defined returns every ID defined by an anchor line in *.adoc files under dir.
func Defined(dir string) (map[string][]Location, error) {
	out := map[string][]Location{}
	err := walk(dir, func(path string) bool { return strings.HasSuffix(path, ".adoc") }, func(path string, n int, line string, state *string) {
		if delimiters[line] {
			if *state == "" {
				*state = line
			} else if *state == line {
				*state = ""
			}
			return
		}
		if *state != "" {
			return
		}
		if m := anchor.FindStringSubmatch(line); m != nil {
			out[m[1]] = append(out[m[1]], Location{path, n})
		}
	})
	return out, err
}

// Cited returns every "<prefix>-NNN" token found in text files under paths.
// Paths that do not exist are skipped.
func Cited(paths []string, prefix string) (map[string][]Location, error) {
	token := regexp.MustCompile(`\b` + regexp.QuoteMeta(prefix) + `-\d{3}\b`)
	out := map[string][]Location{}
	for _, p := range paths {
		if _, err := os.Stat(p); os.IsNotExist(err) {
			continue
		}
		err := walk(p, func(string) bool { return true }, func(path string, n int, line string, _ *string) {
			for _, id := range token.FindAllString(line, -1) {
				out[id] = append(out[id], Location{path, n})
			}
		})
		if err != nil {
			return nil, err
		}
	}
	return out, nil
}

// walk calls fn for each line of each matching file, with CR and a leading BOM removed.
// state is per-file scratch that fn may use to track open blocks.
func walk(root string, match func(string) bool, fn func(path string, n int, line string, state *string)) error {
	return filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !match(path) {
			return err
		}
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		s := bufio.NewScanner(f)
		s.Buffer(make([]byte, 1024*1024), 1024*1024)
		state := ""
		for n := 1; s.Scan(); n++ {
			line := strings.TrimRight(s.Text(), "\r")
			if n == 1 {
				line = strings.TrimPrefix(line, "\ufeff")
			}
			fn(path, n, line, &state)
		}
		return s.Err()
	})
}
