// SPDX-License-Identifier: Apache-2.0

// Command jurisgen generates the jurisdiction comparison pages of an FPSOT spec.
//
// It reads jurisdictions/baseline.yaml and every jurisdiction file, writes one set of
// pages per topic under -out, and warns about rows last checked more than
// -stale-months ago. Stale rows fail the run only with -strict (releases).
//
//	jurisgen -dir jurisdictions -lang en -out docs/modules/en/pages/jurisdictions
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/jurisdiction"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	fl := flag.NewFlagSet("jurisgen", flag.ContinueOnError)
	fl.SetOutput(stderr)
	dir := fl.String("dir", "jurisdictions", "folder holding baseline.yaml and the jurisdiction files")
	lang := fl.String("lang", "", "page language, en or fr (required)")
	out := fl.String("out", "", "folder to write the pages to (required)")
	todayFlag := fl.String("today", "", "date to check against, YYYY-MM-DD (default: today, UTC)")
	months := fl.Int("stale-months", 12, "a row last checked more than this many months ago is stale")
	strict := fl.Bool("strict", false, "fail when a row is stale")
	if err := fl.Parse(args); err != nil {
		return 2
	}
	if *out == "" || (*lang != "en" && *lang != "fr") {
		fmt.Fprintln(stderr, "jurisgen: -out and -lang en|fr are required")
		return 2
	}
	today := time.Now().UTC().Truncate(24 * time.Hour)
	if *todayFlag != "" {
		t, err := time.Parse("2006-01-02", *todayFlag)
		if err != nil {
			fmt.Fprintf(stderr, "jurisgen: -today %q must be YYYY-MM-DD\n", *todayFlag)
			return 2
		}
		today = t
	}
	b, err := jurisdiction.LoadBaseline(filepath.Join(*dir, "baseline.yaml"))
	if err != nil {
		fmt.Fprintf(stderr, "jurisgen: %v\n", err)
		return 1
	}
	files, err := jurisdiction.LoadDir(*dir, b, jurisdiction.LoadOptions{Today: today})
	if err != nil {
		fmt.Fprintf(stderr, "jurisgen: %v\n", err)
		return 1
	}
	if err := jurisdiction.Generate(b, files, jurisdiction.Territories(), *lang, *out); err != nil {
		fmt.Fprintf(stderr, "jurisgen: %v\n", err)
		return 1
	}
	stale := jurisdiction.Stale(files, today, *months)
	for _, s := range stale {
		fmt.Fprintf(stdout, "::warning file=%s::%s last checked %s, more than %d months ago\n", s.Path, s.ID, s.LastChecked.Format("2006-01-02"), *months)
	}
	if *strict && len(stale) > 0 {
		return 1
	}
	return 0
}
