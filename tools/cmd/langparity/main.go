// SPDX-License-Identifier: Apache-2.0

// Command langparity checks that every English page has a translated French page.
//
// Usage: langparity [-strict] ROOT...
// Each ROOT holds en/ and fr/ folders. Without -strict, problems are warnings and the
// exit code is 0, so English-only drafts can merge. With -strict (releases), any missing
// or pending page fails.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/parity"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("langparity", flag.ContinueOnError)
	fs.SetOutput(stderr)
	strict := fs.Bool("strict", false, "fail on any missing or pending page")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() == 0 {
		fmt.Fprintln(stderr, "usage: langparity [-strict] ROOT...")
		return 2
	}
	level := "warning"
	if *strict {
		level = "error"
	}
	problems := 0
	report := func(format string, a ...any) {
		problems++
		fmt.Fprintf(stdout, level+": "+format+"\n", a...)
	}
	for _, root := range fs.Args() {
		for _, lang := range []string{"en", "fr"} {
			if _, err := os.Stat(filepath.Join(root, lang)); os.IsNotExist(err) {
				report("%s: %s/ missing", root, lang)
			}
		}
		r, err := parity.Compare(root)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			fmt.Fprintf(stderr, "langparity: %v\n", err)
			return 2
		}
		for _, p := range r.MissingFR {
			report("%s: fr/%s missing", root, p)
		}
		for _, p := range r.MissingEN {
			report("%s: en/%s missing", root, p)
		}
		for _, p := range r.PendingFR {
			report("%s: fr/%s is marked %q", root, p, parity.PendingMarker)
		}
	}
	if *strict && problems > 0 {
		return 1
	}
	return 0
}
