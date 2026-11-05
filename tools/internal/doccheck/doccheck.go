// SPDX-License-Identifier: Apache-2.0

// Package doccheck checks an FPSOT spec repository against the documentation
// specification: required files, a document history at the end of each page, a
// Diátaxis page type on each docs page, a text alternative on each image, and a
// glossary at the end of each book.
package doccheck

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Finding is one problem.
type Finding struct {
	File string
	Line int
	Msg  string
}

func (f Finding) String() string {
	if f.Line == 0 {
		return fmt.Sprintf("%s: %s", f.File, f.Msg)
	}
	return fmt.Sprintf("%s:%d: %s", f.File, f.Line, f.Msg)
}

// Required lists the files every spec repository must contain.
var Required = []string{
	"README.adoc", "LICENSE.md", "COMMUNITY_SPECIFICATION_LICENSE.md", "NOTICE", "NOTICES.md",
	"CHANGELOG.md", "CONTRIBUTING.md", "CONTRIBUTOR_LICENSE_AGREEMENT.md", "CODE_OF_CONDUCT.md",
	"GOVERNANCE.md", "SCOPE.md", "publiccode.yml", "AGENTS.md", "skill/SKILL.md", ".github/CODEOWNERS",
	"spec/en/index.adoc", "spec/fr/index.adoc", "spec/en/book.adoc", "spec/fr/book.adoc",
}

// PageTypes are the Diátaxis page types.
var PageTypes = []string{"tutorial", "how-to", "reference", "explanation"}

var historyHeading = map[string]string{"en": "Document history", "fr": "Historique du document"}

// RequiredFiles reports each required file missing under root.
func RequiredFiles(root string) []Finding {
	var out []Finding
	for _, p := range Required {
		if _, err := os.Stat(filepath.Join(root, p)); err != nil {
			out = append(out, Finding{root, 0, "required file " + p + " is missing"})
		}
	}
	return out
}

var verbatim = map[string]bool{"----": true, "....": true, "++++": true, "////": true}

// lines calls fn for each line outside verbatim and comment blocks.
func lines(path string, fn func(n int, line string)) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 1024*1024), 1024*1024)
	open := ""
	for n := 1; s.Scan(); n++ {
		line := strings.TrimRight(s.Text(), "\r")
		if n == 1 {
			line = strings.TrimPrefix(line, "\ufeff")
		}
		if verbatim[line] {
			if open == "" {
				open = line
			} else if open == line {
				open = ""
			}
			continue
		}
		if open == "" && !strings.HasPrefix(line, "//") {
			fn(n, line)
		}
	}
	return s.Err()
}

func segments(path string) []string { return strings.Split(filepath.ToSlash(path), "/") }

func langOf(path string) string {
	for _, s := range segments(path) {
		if s == "en" || s == "fr" {
			return s
		}
	}
	return ""
}

func generatedOrBook(path string) bool {
	name := filepath.Base(path)
	if name == "book.adoc" || name == "glossary.adoc" || strings.HasPrefix(name, "_") {
		return true
	}
	for _, s := range segments(path) {
		if s == "jurisdictions" {
			return true
		}
	}
	return false
}

// History reports pages whose last level-1 section is not the document history.
// Books, glossaries, partials and generated jurisdiction pages are skipped.
func History(files []string) []Finding {
	var out []Finding
	for _, file := range files {
		lang := langOf(file)
		if lang == "" || generatedOrBook(file) || !strings.HasSuffix(file, ".adoc") {
			continue
		}
		last, lastLine := "", 0
		err := lines(file, func(n int, line string) {
			if strings.HasPrefix(line, "== ") {
				last, lastLine = strings.TrimSpace(line[3:]), n
			}
		})
		want := historyHeading[lang]
		switch {
		case err != nil:
			out = append(out, Finding{file, 0, err.Error()})
		case last == "":
			out = append(out, Finding{file, 0, fmt.Sprintf("page must end with a \"== %s\" section", want)})
		case last != want:
			out = append(out, Finding{file, lastLine, fmt.Sprintf("last section is %q; the page must end with \"== %s\"", last, want)})
		}
	}
	return out
}

var pageTypeLine = regexp.MustCompile(`^:page-type:\s*(.*?)\s*$`)

// PageType reports docs pages without a valid :page-type: attribute.
func PageType(files []string) []Finding {
	var out []Finding
	for _, file := range files {
		found, value, line := false, "", 0
		lines(file, func(n int, l string) {
			if m := pageTypeLine.FindStringSubmatch(l); m != nil && !found {
				found, value, line = true, m[1], n
			}
		})
		switch {
		case !found:
			out = append(out, Finding{file, 0, "missing :page-type: (one of " + strings.Join(PageTypes, ", ") + ")"})
		case !contains(PageTypes, value):
			out = append(out, Finding{file, line, fmt.Sprintf(":page-type: %q must be one of %s", value, strings.Join(PageTypes, ", "))})
		}
	}
	return out
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

var imageMacro = regexp.MustCompile(`image::?([^\[\s]+)\[([^\]]*)\]`)

// hasAlt reports whether an image's attribute list gives a text alternative: a first
// positional attribute, or alt=.
func hasAlt(attrs string) bool {
	parts := strings.Split(attrs, ",")
	if first := strings.TrimSpace(parts[0]); first != "" && !strings.Contains(first, "=") {
		return true
	}
	for _, p := range parts {
		if k, v, ok := strings.Cut(strings.TrimSpace(p), "="); ok && strings.TrimSpace(k) == "alt" && strings.Trim(strings.TrimSpace(v), `"`) != "" {
			return true
		}
	}
	return false
}

// ImageAlt reports images without a text alternative.
func ImageAlt(files []string) []Finding {
	var out []Finding
	for _, file := range files {
		lines(file, func(n int, l string) {
			for _, m := range imageMacro.FindAllStringSubmatch(l, -1) {
				if !hasAlt(m[2]) {
					out = append(out, Finding{file, n, fmt.Sprintf("image %s has no text alternative", m[1])})
				}
			}
		})
	}
	return out
}

var includeLine = regexp.MustCompile(`^include::([^\[]+)\[`)

// Book reports a book whose last include is not the glossary.
func Book(file string) []Finding {
	last := ""
	if err := lines(file, func(_ int, l string) {
		if m := includeLine.FindStringSubmatch(l); m != nil {
			last = m[1]
		}
	}); err != nil {
		return []Finding{{file, 0, err.Error()}}
	}
	if filepath.Base(last) != "glossary.adoc" {
		return []Finding{{file, 0, "the last include of a book must be glossary.adoc"}}
	}
	return nil
}

var (
	referencesHeading = map[string]string{"en": "References", "fr": "Références"}
	urlPattern        = regexp.MustCompile(`https?://[^\s\[\]<>"]+`)
	monospace         = regexp.MustCompile("`[^`]*`")
	archiveHost       = "https://web.archive.org/"
	linkMacro         = regexp.MustCompile(`(?:link:)?https?://[^\s\[\]]+\[[^\]]*\]`)
	rfcMention        = regexp.MustCompile(`(?:\{abbr-rfc(?:-first)?\}|\bRFC) ?([0-9]{3,5})\b`)
	// A GitHub file link pinned to a full commit hash cannot change: it is its own
	// archived copy.
	pinnedGitHub = regexp.MustCompile(`^https://github\.com/[^/]+/[^/]+/(?:blob|tree)/[0-9a-f]{40}/`)
	sourceAttr   = regexp.MustCompile(`^\[source,\s*[A-Za-z0-9_+-]+`)
)

// outside reports whether url points outside the project: not fpsot.org, not the
// fpsot-org GitHub organisation, not an archived copy and not an example domain.
func outside(url string) bool {
	rest := url[strings.Index(url, "://")+3:]
	host := rest
	if i := strings.IndexAny(rest, "/?#"); i >= 0 {
		host = rest[:i]
	}
	host = strings.ToLower(host)
	switch {
	case host == "fpsot.org" || strings.HasSuffix(host, ".fpsot.org"):
		return false
	case host == "github.com" && strings.HasPrefix(strings.ToLower(rest), "github.com/fpsot-org/"):
		return false
	case strings.HasPrefix(url, archiveHost):
		return false
	}
	for _, ex := range []string{"example.com", "example.org", "example.net"} {
		if host == ex || strings.HasSuffix(host, "."+ex) {
			return false
		}
	}
	return true
}

// References reports, for each page, outside links missing from its References
// section, a References section that is not just before the document history, and
// References entries without an archived copy. Links in code blocks and in
// monospace text are not citations.
func References(files []string) []Finding {
	var out []Finding
	for _, file := range files {
		lang := langOf(file)
		if lang == "" || generatedOrBook(file) || !strings.HasSuffix(file, ".adoc") {
			continue
		}
		type link struct {
			url  string
			line int
		}
		var body []link
		listed := map[string]bool{}
		var sections []string
		refLine, inRefs := 0, false
		err := lines(file, func(n int, line string) {
			if strings.HasPrefix(line, "== ") {
				title := strings.TrimSpace(line[3:])
				sections = append(sections, title)
				inRefs = title == referencesHeading[lang]
				if inRefs {
					refLine = n
				}
				return
			}
			urls := urlPattern.FindAllString(monospace.ReplaceAllString(line, ""), -1)
			if inRefs {
				hasArchive, cites := false, false
				for _, u := range urls {
					if strings.HasPrefix(u, archiveHost) {
						hasArchive = true
					} else if outside(u) {
						listed[u] = true
						cites = true
						if pinnedGitHub.MatchString(u) {
							hasArchive = true
						}
					}
				}
				if cites && !hasArchive {
					out = append(out, Finding{file, n, "references entry has no archived copy (a web.archive.org link, or a GitHub link pinned to a commit)"})
				}
				return
			}
			for _, u := range urls {
				if outside(u) {
					body = append(body, link{u, n})
				}
			}
			// An RFC named outside a link's text is not linked to its source.
			plain := linkMacro.ReplaceAllString(monospace.ReplaceAllString(line, ""), "")
			for _, m := range rfcMention.FindAllStringSubmatch(plain, -1) {
				out = append(out, Finding{file, n, fmt.Sprintf("RFC %s is named without a link to it (https://www.rfc-editor.org/info/rfc%s)", m[1], m[1])})
			}
		})
		if err != nil {
			out = append(out, Finding{file, 0, err.Error()})
			continue
		}
		if refLine != 0 {
			if len(sections) < 2 || sections[len(sections)-2] != referencesHeading[lang] {
				out = append(out, Finding{file, refLine, fmt.Sprintf("\"== %s\" must come just before \"== %s\"", referencesHeading[lang], historyHeading[lang])})
			}
		}
		for _, l := range body {
			if !listed[l.url] {
				if refLine == 0 {
					out = append(out, Finding{file, l.line, fmt.Sprintf("outside link %s needs a \"== %s\" section listing it", l.url, referencesHeading[lang])})
				} else {
					out = append(out, Finding{file, l.line, fmt.Sprintf("outside link %s is not listed under \"== %s\"", l.url, referencesHeading[lang])})
				}
			}
		}
	}
	return out
}

// CodeLanguage reports listing blocks ("----") whose attribute line does not name
// a language with [source,<lang>].
func CodeLanguage(files []string) []Finding {
	var out []Finding
	for _, file := range files {
		if langOf(file) == "" || !strings.HasSuffix(file, ".adoc") {
			continue
		}
		data, err := os.ReadFile(file)
		if err != nil {
			out = append(out, Finding{file, 0, err.Error()})
			continue
		}
		prev, open := "", false
		for i, line := range strings.Split(strings.ReplaceAll(string(data), "\r", ""), "\n") {
			if line == "----" {
				if !open {
					if !sourceAttr.MatchString(prev) {
						out = append(out, Finding{file, i + 1, "code block must name its language, for example [source,json] or [source,text]"})
					}
				}
				open = !open
			}
			if strings.TrimSpace(line) != "" || open {
				prev = line
			}
		}
	}
	return out
}
