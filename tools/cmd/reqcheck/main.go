// SPDX-License-Identifier: Apache-2.0

// Command reqcheck checks requirement IDs in an FPSOT spec repository.
//
// It fails when an ID is defined twice in one language, or when the skill or rules cite
// an ID that no spec page defines. With -strict it also fails when the English and French
// spec text do not define the same IDs; without it, that is a warning.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/fpsot-org/GitHub-Actions/tools/internal/reqid"
)

var languages = []string{"en", "fr"}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("reqcheck", flag.ContinueOnError)
	fs.SetOutput(stderr)
	prefix := fs.String("prefix", "", "requirement ID prefix, three upper-case letters (required)")
	spec := fs.String("spec", "spec", "folder holding en/ and fr/ spec text")
	cite := fs.String("cite", "skill,rules", "comma-separated folders whose citations are checked")
	strict := fs.Bool("strict", false, "fail when en and fr define different IDs")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if len(*prefix) != 3 || strings.ToUpper(*prefix) != *prefix {
		fmt.Fprintln(stderr, "reqcheck: -prefix must be three upper-case letters")
		return 2
	}

	failed := false
	defined := map[string]map[string][]reqid.Location{}
	all := map[string]bool{}
	for _, lang := range languages {
		dir := filepath.Join(*spec, lang)
		ids, err := reqid.Defined(dir)
		if err != nil && !os.IsNotExist(err) {
			fmt.Fprintf(stderr, "reqcheck: %v\n", err)
			return 2
		}
		defined[lang] = ids
		for _, id := range sorted(ids) {
			all[id] = true
			if locs := ids[id]; len(locs) > 1 {
				failed = true
				fmt.Fprintf(stdout, "%s:%d: duplicate %s in %s (also %s:%d)\n", locs[1].File, locs[1].Line, id, lang, locs[0].File, locs[0].Line)
			}
		}
	}

	for _, id := range sorted(all) {
		for _, lang := range languages {
			if defined[lang][id] == nil {
				level := "warning"
				if *strict {
					level, failed = "error", true
				}
				fmt.Fprintf(stdout, "%s: %s defined in another language but not in %s\n", level, id, lang)
			}
		}
	}

	cited, err := reqid.Cited(strings.Split(*cite, ","), *prefix)
	if err != nil {
		fmt.Fprintf(stderr, "reqcheck: %v\n", err)
		return 2
	}
	for _, id := range sorted(cited) {
		if !all[id] {
			failed = true
			loc := cited[id][0]
			fmt.Fprintf(stdout, "%s:%d: %s is cited but not defined in the spec\n", loc.File, loc.Line, id)
		}
	}

	if failed {
		return 1
	}
	return 0
}

func sorted[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
