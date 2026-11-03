// SPDX-License-Identifier: Apache-2.0

// Command sitecollect turns one generated FPSOT spec repository into content for
// the fpsot.org site. It writes one page per spec page at its site URL, rewrites
// links between pages to site URLs, and copies the diagrams.
//
//	sitecollect -spec writing -src . -out SITE/content -public SITE/public \
//	  -version 0.1.1 -dates dates.tsv -default-date 2026-11-03 \
//	  -repo-url https://github.com/fpsot-org/fpsot-spec-writing
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/site"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	fl := flag.NewFlagSet("sitecollect", flag.ContinueOnError)
	fl.SetOutput(stderr)
	spec := fl.String("spec", "", "spec name, such as writing (required)")
	src := fl.String("src", ".", "the spec repository, already generated")
	out := fl.String("out", "", "the site's content folder (required)")
	public := fl.String("public", "", "the site's static folder (default: <out>/public)")
	root := fl.String("root", "", "URL root of the spec without the language (default: /<spec>)")
	version := fl.String("version", "", "spec version, such as 0.1.1 (required)")
	dates := fl.String("dates", "", "TSV file of source path and last change date")
	defaultDate := fl.String("default-date", "", "date of files missing from -dates (required)")
	repoURL := fl.String("repo-url", "", "https URL of the spec repository (required)")
	siteURL := fl.String("site-url", "https://fpsot.org", "https URL of the site")
	if err := fl.Parse(args); err != nil {
		return 2
	}
	if *spec == "" || *out == "" || *version == "" || *defaultDate == "" || *repoURL == "" {
		fmt.Fprintln(stderr, "sitecollect: -spec, -out, -version, -default-date and -repo-url are required")
		return 2
	}
	if *root == "" {
		*root = "/" + *spec
	}
	d := map[string]string{}
	if *dates != "" {
		var err error
		if d, err = site.LoadDates(*dates); err != nil {
			fmt.Fprintln(stderr, "sitecollect:", err)
			return 1
		}
	}
	err := site.Collect(site.Options{Spec: *spec, Root: *root, SrcDir: *src, OutDir: *out, PublicDir: *public,
		Version: *version, Dates: d, DefaultDate: *defaultDate, RepoURL: *repoURL, SiteURL: *siteURL})
	if err != nil {
		fmt.Fprintln(stderr, "sitecollect:", err)
		return 1
	}
	fmt.Fprintf(stdout, "sitecollect: %s %s collected\n", *spec, *version)
	return 0
}
