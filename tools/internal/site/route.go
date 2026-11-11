// SPDX-License-Identifier: Apache-2.0

// Package site turns a generated FPSOT spec repository into content for the
// fpsot.org site: it maps each page to its URL, rewrites links between pages to
// site URLs, and writes the page attributes the site layouts read.
package site

import (
	"fmt"
	"path"
	"strings"
)

// Page is one page of a spec and its place on the site.
type Page struct {
	Src  string // path in the spec repository, with slashes
	Lang string // "en" or "fr"
	URL  string // site path with the language prefix, ending in "/"
}

// Reserved names cannot be spec page names: the site uses them as folders.
var Reserved = []string{"guides", "compare", "diagrams"}

func langPrefix(lang string) string {
	if lang == "fr" {
		return "/fr"
	}
	return ""
}

// dirURL turns a page path relative to its section ("index.adoc", "a/b.adoc")
// into a URL part ending in "/".
func dirURL(rel string) string {
	rel = strings.TrimSuffix(rel, ".adoc")
	rel = strings.TrimSuffix(rel, "index")
	if rel != "" && !strings.HasSuffix(rel, "/") {
		rel += "/"
	}
	return rel
}

// Route maps a source file to its page. ok is false for files that are not pages:
// partials (names starting with "_"), non-AsciiDoc files and files outside spec/<lang>/
// and docs/modules/<lang>/pages/. root is the URL root of the spec without the
// language, such as "/writing".
func Route(spec, root, src string) (Page, bool, error) {
	name := path.Base(src)
	if !strings.HasSuffix(name, ".adoc") || strings.HasPrefix(name, "_") {
		return Page{}, false, nil
	}
	parts := strings.Split(src, "/")
	var lang, rest string
	switch {
	case len(parts) >= 3 && parts[0] == "spec":
		lang = parts[1]
		// The first name under spec/<lang>/, a page or a folder, is a folder on the site.
		page := strings.TrimSuffix(parts[2], ".adoc")
		for _, r := range Reserved {
			if page == r {
				return Page{}, false, fmt.Errorf("%s: %q is a reserved name on the site (%s)", src, page, strings.Join(Reserved, ", "))
			}
		}
		rest = dirURL(strings.Join(parts[2:], "/"))
	case len(parts) >= 5 && parts[0] == "docs" && parts[1] == "modules" && parts[3] == "pages":
		lang = parts[2]
		in := strings.Join(parts[4:], "/")
		if strings.HasPrefix(in, "jurisdictions/") {
			rest = "compare/" + dirURL(strings.TrimPrefix(in, "jurisdictions/"))
		} else {
			rest = "guides/" + dirURL(in)
		}
	default:
		return Page{}, false, nil
	}
	if lang != "en" && lang != "fr" {
		return Page{}, false, nil
	}
	return Page{Src: src, Lang: lang, URL: langPrefix(lang) + strings.TrimSuffix(root, "/") + "/" + rest}, true, nil
}

// otherLangCode returns "fr" for "en", and "en" for "fr".
func otherLangCode(lang string) string {
	if lang == "fr" {
		return "en"
	}
	return "fr"
}

// otherLang returns the source path of the same page in the other language.
func otherLang(p Page) string {
	other := otherLangCode(p.Lang)
	parts := strings.Split(p.Src, "/")
	if parts[0] == "spec" {
		parts[1] = other
	} else {
		parts[2] = other
	}
	return strings.Join(parts, "/")
}
