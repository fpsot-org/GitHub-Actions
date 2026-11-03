// SPDX-License-Identifier: Apache-2.0

// Command doccheck checks an FPSOT spec repository against the documentation rules:
// required files, a document history at the end of each page, a page type on each docs
// page, a text alternative on each image, and a glossary at the end of each book.
//
//	doccheck -root .
package main

import (
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/doccheck"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	fl := flag.NewFlagSet("doccheck", flag.ContinueOnError)
	fl.SetOutput(stderr)
	root := fl.String("root", ".", "spec repository to check")
	if err := fl.Parse(args); err != nil {
		return 2
	}
	spec := adoc(filepath.Join(*root, "spec"))
	docs := adoc(filepath.Join(*root, "docs", "modules"))
	var pages []string
	for _, p := range docs {
		if strings.Contains(filepath.ToSlash(p), "/pages/") {
			pages = append(pages, p)
		}
	}
	var findings []doccheck.Finding
	findings = append(findings, doccheck.RequiredFiles(*root)...)
	all := append(append([]string{}, spec...), pages...)
	findings = append(findings, doccheck.History(all)...)
	var authored []string
	for _, p := range pages {
		if !strings.Contains(filepath.ToSlash(p), "/jurisdictions/") && !strings.HasPrefix(filepath.Base(p), "_") {
			authored = append(authored, p)
		}
	}
	findings = append(findings, doccheck.PageType(authored)...)
	findings = append(findings, doccheck.ImageAlt(all)...)
	for _, lang := range []string{"en", "fr"} {
		book := filepath.Join(*root, "spec", lang, "book.adoc")
		if _, err := os.Stat(book); err == nil {
			findings = append(findings, doccheck.Book(book)...)
		}
	}
	for _, f := range findings {
		fmt.Fprintln(stdout, f)
	}
	if len(findings) > 0 {
		return 1
	}
	return 0
}

func adoc(dir string) []string {
	var out []string
	filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.HasSuffix(p, ".adoc") {
			out = append(out, p)
		}
		return nil
	})
	return out
}
