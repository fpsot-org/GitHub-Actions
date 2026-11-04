// SPDX-License-Identifier: Apache-2.0

package site

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Options of one Collect run.
type Options struct {
	Spec        string            // spec name, such as "writing"
	Root        string            // URL root without the language, such as "/writing"
	SrcDir      string            // the spec repository, already generated
	OutDir      string            // the site's content folder
	PublicDir   string            // the site's static folder; default OutDir/public
	Version     string            // spec version, such as "0.1.1"
	Dates       map[string]string // last change date of each source file
	DefaultDate string            // date for files missing from Dates
	RepoURL     string            // https URL of the spec repository
	SiteURL     string            // https URL of the site

	route func(spec, root, src string) (Page, bool, error) // test hook
}

// frenchLabels are Asciidoctor's French labels, set on French pages.
var frenchLabels = [][2]string{
	{"toc-title", "Table des matières"}, {"table-caption", "Tableau"}, {"example-caption", "Exemple"},
	{"figure-caption", "Figure"}, {"note-caption", "Note"}, {"tip-caption", "Astuce"},
	{"important-caption", "Important"}, {"warning-caption", "Avertissement"}, {"caution-caption", "Attention"},
	{"appendix-caption", "Annexe"}, {"chapter-signifier", "Chapitre"}, {"part-signifier", "Partie"},
	{"untitled-label", "Sans titre"}, {"version-label", "Version"},
}

// LoadDates reads a TSV file of "source path<TAB>YYYY-MM-DD" lines.
func LoadDates(file string) (map[string]string, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	out := map[string]string{}
	s := bufio.NewScanner(f)
	for n := 1; s.Scan(); n++ {
		line := strings.TrimSpace(s.Text())
		if line == "" {
			continue
		}
		src, date, ok := strings.Cut(line, "\t")
		if !ok {
			return nil, fmt.Errorf("%s:%d: want \"path<TAB>date\"", file, n)
		}
		out[src] = date
	}
	return out, s.Err()
}

// Collect writes the site content of one spec: a mirror of its AsciiDoc sources
// with links rewritten, under OutDir/_src/<spec>/, one page file per page at its
// URL, and its diagrams under PublicDir.
func Collect(opt Options) error {
	route := opt.route
	if route == nil {
		route = Route
	}
	if opt.PublicDir == "" {
		opt.PublicDir = filepath.Join(opt.OutDir, "public")
	}
	var files []string
	for _, top := range []string{"spec", "docs", "diagrams"} {
		root := filepath.Join(opt.SrcDir, top)
		if _, err := os.Stat(root); err != nil {
			continue
		}
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			rel, _ := filepath.Rel(opt.SrcDir, p)
			files = append(files, filepath.ToSlash(rel))
			return nil
		})
		if err != nil {
			return err
		}
	}
	sort.Strings(files)

	pages := map[string]Page{}   // by source
	byURL := map[string]string{} // URL → source
	exists := map[string]bool{}
	var problems []string
	for _, src := range files {
		exists[src] = true
		p, ok, err := route(opt.Spec, opt.Root, src)
		if err != nil {
			problems = append(problems, err.Error())
			continue
		}
		if !ok {
			continue
		}
		if other, dup := byURL[p.URL]; dup {
			problems = append(problems, fmt.Sprintf("%s and %s both map to %s", other, src, p.URL))
			continue
		}
		byURL[p.URL] = src
		pages[src] = p
	}
	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "\n"))
	}
	root := strings.TrimSuffix(opt.Root, "/")
	resolve := func(target string) (string, bool) {
		if strings.HasPrefix(target, "diagrams/") && exists[target] {
			return root + "/" + target, true
		}
		p, ok := pages[target]
		return p.URL, ok
	}

	// The title of each language's spec index names the spec on every page.
	specTitles := map[string]string{}
	for _, lang := range []string{"en", "fr"} {
		if body, err := os.ReadFile(filepath.Join(opt.SrcDir, "spec", lang, "index.adoc")); err == nil {
			if title, _, _ := strings.Cut(string(body), "\n"); strings.HasPrefix(title, "= ") {
				specTitles[lang] = strings.TrimSpace(strings.TrimPrefix(title, "= "))
			}
		}
	}
	mirror := filepath.Join(opt.OutDir, "_src", opt.Spec)
	for _, src := range files {
		from := filepath.Join(opt.SrcDir, filepath.FromSlash(src))
		if strings.HasPrefix(src, "diagrams/") {
			if strings.HasSuffix(src, ".svg") {
				if err := copyFile(from, filepath.Join(opt.PublicDir, filepath.FromSlash(strings.TrimPrefix(root, "/")), filepath.FromSlash(src))); err != nil {
					return err
				}
			}
			continue
		}
		if !strings.HasSuffix(src, ".adoc") {
			continue
		}
		body, err := os.ReadFile(from)
		if err != nil {
			return err
		}
		out, probs := Rewrite(body, src, resolve)
		problems = append(problems, probs...)
		if err := write(filepath.Join(mirror, filepath.FromSlash(src)), out); err != nil {
			return err
		}
		if p, ok := pages[src]; ok {
			page, err := pageFile(opt, p, body, pages, mirror, specTitles[p.Lang])
			if err != nil {
				problems = append(problems, err.Error())
				continue
			}
			if err := write(filepath.Join(opt.OutDir, filepath.FromSlash(strings.TrimPrefix(p.URL, "/")), "index.adoc"), page); err != nil {
				return err
			}
		}
	}
	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "\n"))
	}
	return nil
}

// pageFile builds the page Roq renders: the source's title, the header block, and
// an include of the rest of the source from the mirror.
func pageFile(opt Options, p Page, body []byte, pages map[string]Page, mirror, specTitle string) ([]byte, error) {
	title, _, _ := strings.Cut(string(body), "\n")
	title = strings.TrimRight(strings.TrimPrefix(title, "\ufeff"), "\r")
	if !strings.HasPrefix(title, "= ") {
		return nil, fmt.Errorf("%s: the first line must be the page title (\"= …\")", p.Src)
	}
	date := opt.Dates[p.Src]
	if date == "" {
		date = opt.DefaultDate
	}
	var b strings.Builder
	line := func(k, v string) { fmt.Fprintf(&b, ":%s: %s\n", k, v) }
	b.WriteString(title + "\n")
	line("page-layout", "spec")
	line("page-link", p.URL)
	line("page-lang", p.Lang)
	line("page-spec", opt.Spec)
	if specTitle != "" {
		line("page-spec-title", specTitle)
	}
	line("page-version", opt.Version)
	line("page-updated", date)
	if alt, ok := pages[otherLang(p)]; ok {
		line("page-alternate", alt.URL)
	}
	line("revnumber", opt.Version)
	line("contributing-url", strings.TrimSuffix(opt.RepoURL, "/")+"/blob/main/CONTRIBUTING.md")
	line("spec-repo-url", opt.RepoURL)
	line("fpsot-site", opt.SiteURL)
	if p.Lang == "fr" {
		for _, kv := range frenchLabels {
			line(kv[0], kv[1])
		}
	}
	// Roq's AsciidoctorJ resolves an include only by absolute path, so the page
	// points at its source in the mirror by absolute path.
	abs, err := filepath.Abs(filepath.Join(mirror, filepath.FromSlash(p.Src)))
	if err != nil {
		return nil, err
	}
	n := strings.Count(string(body), "\n")
	if !strings.HasSuffix(string(body), "\n") {
		n++
	}
	// The open range "2..-1" is ignored, so the range names the last line.
	fmt.Fprintf(&b, "\ninclude::%s[lines=2..%d]\n", filepath.ToSlash(abs), n)
	return []byte(b.String()), nil
}

func write(p string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.WriteFile(p, data, 0o644)
}

func copyFile(from, to string) error {
	data, err := os.ReadFile(from)
	if err != nil {
		return err
	}
	return write(to, data)
}
