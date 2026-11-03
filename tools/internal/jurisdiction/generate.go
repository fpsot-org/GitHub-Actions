// SPDX-License-Identifier: Apache-2.0

package jurisdiction

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/text/collate"
	"golang.org/x/text/language"
)

type labels struct {
	indexTitle, defaults, jurisdictions, documented, back, subdivisions, stub, archived, disclaimer string
	columns                                                                                         [7]string
}

var text = map[string]labels{
	"en": {
		indexTitle:    "%s: comparison by jurisdiction",
		defaults:      "FPSOT default and international baseline",
		jurisdictions: "Jurisdictions",
		documented:    "(documented)",
		back:          "Back to",
		subdivisions:  "Documented subdivisions",
		stub:          "This jurisdiction is not documented yet for this topic. To add it, see link:{contributing-url}[how to contribute].",
		archived:      "Archived copy",
		disclaimer:    "This comparison is informational. It is not legal advice.",
		columns:       [7]string{"Requirement", "International baseline", "FPSOT default", "This jurisdiction", "Status", "Source and version", "Last checked"},
	},
	"fr": {
		indexTitle:    "%s : comparaison par territoire",
		defaults:      "Valeur FPSOT et référence internationale",
		jurisdictions: "Territoires",
		documented:    "(documenté)",
		back:          "Retour à",
		subdivisions:  "Subdivisions documentées",
		stub:          "Ce territoire n'est pas encore documenté pour ce sujet. Pour l'ajouter, voir link:{contributing-url}[comment contribuer].",
		archived:      "Copie archivée",
		disclaimer:    "Cette comparaison est informative. Elle ne constitue pas un avis juridique.",
		columns:       [7]string{"Exigence", "Référence internationale", "Valeur FPSOT", "Ce territoire", "Statut", "Source et version", "Dernière vérification"},
	},
}

// cell escapes a value for an AsciiDoc table cell.
func cell(s string) string { return strings.ReplaceAll(s, "|", `\|`) }

func titleSep(lang string) string {
	if lang == "fr" {
		return " : "
	}
	return ": "
}

func sourceCell(s Source, l labels) string {
	parts := []string{fmt.Sprintf("link:%s[%s]", s.URL, strings.ReplaceAll(s.Title, "]", `\]`))}
	if s.Version != "" {
		parts = append(parts, s.Version)
	}
	if s.Date != "" {
		parts = append(parts, s.Date)
	}
	return cell(strings.Join(parts, ", ") + ". " + fmt.Sprintf("link:%s[%s]", s.Archive, l.archived))
}

func header(title string, l labels) string {
	return fmt.Sprintf("= %s\n:page-type: reference\n\n[NOTE]\n====\n%s\n====\n\n", title, l.disclaimer)
}

func write(path, body string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(body), 0o644)
}

// Generate writes the jurisdiction pages of every topic, in one language, under outDir.
func Generate(b *Baseline, files []File, t *Territory, lang, outDir string) error {
	l, ok := text[lang]
	if !ok {
		return fmt.Errorf("unsupported language %q", lang)
	}
	tag := language.CanadianFrench
	if lang != "fr" {
		tag = language.English
	}
	coll := collate.New(tag, collate.IgnoreCase)
	byCode := map[string]File{}
	subsOf := map[string][]File{}
	for _, f := range files {
		byCode[f.Code] = f
		if f.IsSubdivision() {
			subsOf[f.Country()] = append(subsOf[f.Country()], f)
		}
	}
	topics := make([]string, 0, len(b.Topics))
	for id := range b.Topics {
		topics = append(topics, id)
	}
	sort.Strings(topics)
	for _, topic := range topics {
		g := gen{b: b, t: t, lang: lang, l: l, topic: topic, name: b.Topics[topic].In(lang), coll: coll, byCode: byCode, subsOf: subsOf}
		if err := g.all(filepath.Join(outDir, topic)); err != nil {
			return err
		}
	}
	return nil
}

type gen struct {
	b      *Baseline
	t      *Territory
	lang   string
	l      labels
	topic  string
	name   string
	coll   *collate.Collator
	byCode map[string]File
	subsOf map[string][]File
}

func (g gen) rows() []BaselineRow {
	var out []BaselineRow
	for _, r := range g.b.Rows {
		if r.Topic == g.topic {
			out = append(out, r)
		}
	}
	return out
}

// documented returns the file's rows for this topic, in baseline order.
func (g gen) documented(f File) []Row {
	in := map[string]Row{}
	for _, r := range f.Rows {
		in[r.ID] = r
	}
	var out []Row
	for _, br := range g.rows() {
		if r, ok := in[br.ID]; ok {
			out = append(out, r)
		}
	}
	return out
}

func (g gen) hasData(code string) bool {
	if f, ok := g.byCode[code]; ok && len(g.documented(f)) > 0 {
		return true
	}
	for _, s := range g.subsOf[code] {
		if len(g.documented(s)) > 0 {
			return true
		}
	}
	return false
}

func (g gen) all(dir string) error {
	if err := write(filepath.Join(dir, "index.adoc"), g.index()); err != nil {
		return err
	}
	for _, r := range g.t.Continents() {
		if err := write(filepath.Join(dir, "region-"+r.Code+".adoc"), g.region(r)); err != nil {
			return err
		}
		for _, c := range r.Countries {
			cc := strings.ToLower(c)
			if err := write(filepath.Join(dir, cc, "index.adoc"), g.country(c, r)); err != nil {
				return err
			}
			for _, s := range g.subsOf[c] {
				sub := strings.ToLower(s.Code[3:])
				if err := write(filepath.Join(dir, cc, sub+".adoc"), g.subdivision(s, c)); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

func (g gen) index() string {
	var sb strings.Builder
	sb.WriteString(header(fmt.Sprintf(g.l.indexTitle, g.name), g.l))
	fmt.Fprintf(&sb, "== %s\n\n[cols=\"2,3,3\",options=\"header\"]\n|===\n|%s |%s |%s\n", g.l.defaults, g.l.columns[0], g.l.columns[1], g.l.columns[2])
	for _, r := range g.rows() {
		fmt.Fprintf(&sb, "\n|%s: %s\n|%s %s\n|%s\n", r.ID, cell(r.Requirement.In(g.lang)), cell(r.International.In(g.lang)), sourceCell(r.InternationalSource, g.l), cell(r.FPSOT.In(g.lang)))
	}
	fmt.Fprintf(&sb, "|===\n\n== %s\n\n", g.l.jurisdictions)
	for _, r := range g.t.Continents() {
		fmt.Fprintf(&sb, "* xref:region-%s.adoc[%s]\n", r.Code, r.Name[g.lang])
	}
	return sb.String()
}

func (g gen) region(r Region) string {
	var sb strings.Builder
	sb.WriteString(header(g.name+titleSep(g.lang)+r.Name[g.lang], g.l))
	fmt.Fprintf(&sb, "%s xref:index.adoc[%s].\n\n", g.l.back, g.name)
	countries := append([]string(nil), r.Countries...)
	sort.SliceStable(countries, func(i, j int) bool {
		return g.coll.CompareString(g.t.CountryName(countries[i], g.lang), g.t.CountryName(countries[j], g.lang)) < 0
	})
	for _, c := range countries {
		mark := ""
		if g.hasData(c) {
			mark = " " + g.l.documented
		}
		fmt.Fprintf(&sb, "* xref:%s/index.adoc[%s]%s\n", strings.ToLower(c), g.t.CountryName(c, g.lang), mark)
	}
	return sb.String()
}

func (g gen) table(f File) string {
	rows := g.documented(f)
	if len(rows) == 0 {
		return g.l.stub + "\n"
	}
	base := map[string]BaselineRow{}
	for _, r := range g.rows() {
		base[r.ID] = r
	}
	var sb strings.Builder
	c := g.l.columns
	fmt.Fprintf(&sb, "[cols=\"2,2,2,2,1,2,1\",options=\"header\"]\n|===\n|%s |%s |%s |%s |%s |%s |%s\n", c[0], c[1], c[2], c[3], c[4], c[5], c[6])
	for _, r := range rows {
		br := base[r.ID]
		fmt.Fprintf(&sb, "\n|%s: %s\n|%s\n|%s\n|%s\n|%s\n|%s\n|%s\n", r.ID, cell(br.Requirement.In(g.lang)), cell(br.International.In(g.lang)),
			cell(br.FPSOT.In(g.lang)), cell(r.Text.In(g.lang)), statusLabel[r.Status].In(g.lang), sourceCell(r.Source, g.l), r.LastChecked)
	}
	sb.WriteString("|===\n")
	return sb.String()
}

func (g gen) country(code string, r Region) string {
	var sb strings.Builder
	sb.WriteString(header(g.name+titleSep(g.lang)+g.t.CountryName(code, g.lang), g.l))
	fmt.Fprintf(&sb, "%s xref:../region-%s.adoc[%s].\n\n", g.l.back, r.Code, r.Name[g.lang])
	f, ok := g.byCode[code]
	if ok {
		sb.WriteString(g.table(f))
	} else {
		sb.WriteString(g.l.stub + "\n")
	}
	subs := g.subsOf[code]
	if len(subs) > 0 {
		fmt.Fprintf(&sb, "\n== %s\n\n", g.l.subdivisions)
		sort.SliceStable(subs, func(i, j int) bool { return g.coll.CompareString(subs[i].Name.In(g.lang), subs[j].Name.In(g.lang)) < 0 })
		for _, s := range subs {
			fmt.Fprintf(&sb, "* xref:%s.adoc[%s]\n", strings.ToLower(s.Code[3:]), s.Name.In(g.lang))
		}
	}
	return sb.String()
}

func (g gen) subdivision(f File, country string) string {
	var sb strings.Builder
	sb.WriteString(header(g.name+titleSep(g.lang)+f.Name.In(g.lang), g.l))
	fmt.Fprintf(&sb, "%s xref:index.adoc[%s].\n\n", g.l.back, g.t.CountryName(country, g.lang))
	sb.WriteString(g.table(f))
	return sb.String()
}
