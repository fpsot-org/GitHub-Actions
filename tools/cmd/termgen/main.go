// SPDX-License-Identifier: Apache-2.0

// Command termgen turns the FPSOT term base into AsciiDoc for one language.
//
// It writes the attribute definitions ({abbr-ID}, {abbr-ID-first}, {term-ID}) that
// pages include, and optionally a glossary of the terms the pages use. It then
// checks the pages and exits 1 when a page refers to an unknown term or uses an
// abbreviation before spelling it out.
//
//	termgen -termbase terms.yaml -lang en -attrs spec/en/_fpsot-terms.adoc \
//	  -glossary spec/en/glossary.adoc spec/en
package main

import (
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/termbase"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	fl := flag.NewFlagSet("termgen", flag.ContinueOnError)
	fl.SetOutput(stderr)
	tb := fl.String("termbase", "", "term base file (required)")
	lang := fl.String("lang", "", "page language, en or fr (required)")
	attrs := fl.String("attrs", "", "attribute file to write (required)")
	xref := fl.String("glossary-xref", "glossary.adoc", "glossary path as seen from the pages")
	gloss := fl.String("glossary", "", "glossary file to write (optional)")
	if err := fl.Parse(args); err != nil {
		return 2
	}
	if *tb == "" || *attrs == "" || (*lang != "en" && *lang != "fr") {
		fmt.Fprintln(stderr, "termgen: -termbase, -attrs and -lang en|fr are required")
		return 2
	}
	base, err := termbase.Load(*tb)
	if err != nil {
		fmt.Fprintf(stderr, "termgen: %v\n", err)
		return 1
	}
	pages, err := collect(fl.Args())
	if err != nil {
		fmt.Fprintf(stderr, "termgen: %v\n", err)
		return 1
	}
	if err := os.WriteFile(*attrs, []byte(base.Attributes(*lang, *xref)), 0o644); err != nil {
		fmt.Fprintf(stderr, "termgen: %v\n", err)
		return 1
	}
	if *gloss != "" {
		used, err := termbase.Used(pages)
		if err != nil {
			fmt.Fprintf(stderr, "termgen: %v\n", err)
			return 1
		}
		if err := os.WriteFile(*gloss, []byte(base.Glossary(*lang, used)), 0o644); err != nil {
			fmt.Fprintf(stderr, "termgen: %v\n", err)
			return 1
		}
	}
	findings := base.Check(pages)
	for _, f := range findings {
		fmt.Fprintln(stdout, f)
	}
	if len(findings) > 0 {
		return 1
	}
	return 0
}

// collect expands directories into their .adoc files, skipping partials (names
// starting with "_") and generated glossaries.
func collect(args []string) ([]string, error) {
	var out []string
	for _, a := range args {
		info, err := os.Stat(a)
		if err != nil {
			return nil, err
		}
		if !info.IsDir() {
			out = append(out, a)
			continue
		}
		err = filepath.WalkDir(a, func(p string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			name := d.Name()
			if strings.HasSuffix(name, ".adoc") && !strings.HasPrefix(name, "_") && name != "glossary.adoc" {
				out = append(out, p)
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return out, nil
}
