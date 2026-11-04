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
	crossRe = regexp.MustCompile(`<<([^<>#,\s]+\.adoc)(#[^,>]*)?(?:,([^>]*))?>>`)
	imageRe = regexp.MustCompile(`(image::?)([^\[\s:]+)\[`)
)

// listing delimiters: lines between a pair are code, and are left unchanged.
var listing = map[string]bool{"----": true, "....": true, "++++": true}

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
		if listing[trimmed] {
			switch open {
			case "":
				open = trimmed
			case trimmed:
				open = ""
			}
			continue
		}
		if open != "" || strings.HasPrefix(line, "//") {
			continue
		}
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
			u, ok := target(g[1])
			if !ok {
				return m
			}
			return "link:" + u + g[2] + "[" + g[3] + "]"
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
		lines[i] = []byte(line)
	}
	return bytes.Join(lines, []byte("\n")), problems
}
