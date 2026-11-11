// SPDX-License-Identifier: Apache-2.0

package site

import (
	"bytes"
	"fmt"
	"path"
	"regexp"
	"strings"
)

var (
	xrefRe  = regexp.MustCompile(`xref:([^\[\s#]+\.adoc)(#[^\[\s]*)?\[`)
	crossRe = regexp.MustCompile(`<<([^<>#,\s]+)(#[^,>]*)?(?:,([^>]*))?>>`)
	imageRe = regexp.MustCompile(`\b(image::?)([^\[\s:]+)\[`)
	// Delimiters of listing, literal, passthrough and comment blocks (four or more
	// of the same character), and of fenced code: lines inside are left unchanged.
	blockRe = regexp.MustCompile("^(-{4,}|\\.{4,}|\\+{4,}|/{4,}|```.*)$")
	// Inline passthroughs (+…+, ++…++, +++…+++, pass:[…]) keep their text as written.
	passRe = regexp.MustCompile(`\+\+\+.+?\+\+\+|\+\+.+?\+\+|\+[^+\s](?:[^+]*?[^+\s])?\+|pass:[a-z,]*\[(?:[^\]\\]|\\.)*\]`)
)

// blockKey is the line that closes the block a delimiter line opens.
func blockKey(line string) string {
	if strings.HasPrefix(line, "```") {
		return "```"
	}
	return line
}

// Rewrite changes every link to another page into a site URL, and every relative
// image path into its site path. Targets resolve relative to fromSrc's folder.
// In-page references (xref:#id[], <<id>>) are left as they are. It returns the
// new body and one problem for each target that does not resolve.
func Rewrite(body []byte, fromSrc string, resolve func(targetSrc string) (string, bool)) ([]byte, []string) {
	dir := path.Dir(fromSrc)
	var problems []string
	target := func(t string) (string, bool) {
		src := path.Clean(path.Join(dir, t))
		u, ok := resolve(src)
		if !ok {
			problems = append(problems, fmt.Sprintf("%s: link target %s (%s) does not resolve", fromSrc, t, src))
		}
		return u, ok
	}
	lines := bytes.Split(body, []byte("\n"))
	open := ""
	for i, raw := range lines {
		line := string(raw)
		trimmed := strings.TrimRight(line, "\r")
		if blockRe.MatchString(trimmed) {
			switch open {
			case "":
				open = blockKey(trimmed)
			case trimmed:
				open = ""
			}
			continue
		}
		if open != "" || strings.HasPrefix(line, "//") {
			continue
		}
		// Passthroughs are set aside while the links are rewritten.
		var kept []string
		line = passRe.ReplaceAllStringFunc(line, func(m string) string {
			kept = append(kept, m)
			return fmt.Sprintf("\x00%d\x00", len(kept)-1)
		})
		line = xrefRe.ReplaceAllStringFunc(line, func(m string) string {
			g := xrefRe.FindStringSubmatch(m)
			u, ok := target(g[1])
			if !ok {
				return m
			}
			return "link:" + u + g[2] + "["
		})
		line = crossRe.ReplaceAllStringFunc(line, func(m string) string {
			g := crossRe.FindStringSubmatch(m)
			doc := g[1]
			if !strings.HasSuffix(doc, ".adoc") {
				if g[2] == "" {
					return m // <<id>>: in the page
				}
				doc += ".adoc" // <<doc#id>>
			}
			u, ok := target(doc)
			if !ok {
				return m
			}
			return "link:" + u + g[2] + "[" + strings.ReplaceAll(g[3], "]", "\\]") + "]"
		})
		line = imageRe.ReplaceAllStringFunc(line, func(m string) string {
			g := imageRe.FindStringSubmatch(m)
			if strings.HasPrefix(g[2], "/") || strings.HasPrefix(g[2], "{") {
				return m
			}
			u, ok := target(g[2])
			if !ok {
				return m
			}
			return g[1] + u + "["
		})
		for k, m := range kept {
			line = strings.Replace(line, fmt.Sprintf("\x00%d\x00", k), m, 1)
		}
		lines[i] = []byte(line)
	}
	return bytes.Join(lines, []byte("\n")), problems
}
