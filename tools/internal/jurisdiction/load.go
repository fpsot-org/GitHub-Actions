// SPDX-License-Identifier: Apache-2.0

package jurisdiction

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

var (
	rowID    = regexp.MustCompile(`^[A-Z]{3}-\d{3}$`)
	codeForm = regexp.MustCompile(`^[A-Z]{2}(-[A-Z0-9]{1,3})?$`)
	topicID  = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
)

func decode(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(v); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

func needText(path, what string, t Text) error {
	if strings.TrimSpace(t.EN) == "" || strings.TrimSpace(t.FR) == "" {
		return fmt.Errorf("%s: %s needs en and fr", path, what)
	}
	return nil
}

func needSource(path, what string, s Source) error {
	if s.Title == "" || s.URL == "" || s.Archive == "" {
		return fmt.Errorf("%s: %s needs title, url and archive", path, what)
	}
	return nil
}

// LoadBaseline reads and validates jurisdictions/baseline.yaml.
func LoadBaseline(path string) (*Baseline, error) {
	var b Baseline
	if err := decode(path, &b); err != nil {
		return nil, err
	}
	for id, name := range b.Topics {
		if !topicID.MatchString(id) {
			return nil, fmt.Errorf("%s: topic %q: id must match %s", path, id, topicID)
		}
		if err := needText(path, "topic "+id, name); err != nil {
			return nil, err
		}
	}
	b.byID = map[string]*BaselineRow{}
	for i := range b.Rows {
		r := &b.Rows[i]
		what := "row " + r.ID
		switch {
		case !rowID.MatchString(r.ID):
			return nil, fmt.Errorf("%s: row %q: id must be a requirement ID such as WRT-001", path, r.ID)
		case b.byID[r.ID] != nil:
			return nil, fmt.Errorf("%s: row %s appears twice", path, r.ID)
		case b.Topics[r.Topic] == (Text{}):
			return nil, fmt.Errorf("%s: row %s: unknown topic %q", path, r.ID, r.Topic)
		}
		for name, t := range map[string]Text{"requirement": r.Requirement, "international": r.International, "fpsot": r.FPSOT} {
			if err := needText(path, what+" "+name, t); err != nil {
				return nil, err
			}
		}
		if err := needSource(path, what+" international_source", r.InternationalSource); err != nil {
			return nil, err
		}
		b.byID[r.ID] = r
	}
	return &b, nil
}

// LoadDir reads every jurisdiction file under dir (all *.yaml except baseline.yaml),
// sorted by code.
func LoadDir(dir string, b *Baseline, opt LoadOptions) ([]File, error) {
	var files []File
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".yaml") {
			return err
		}
		rel, _ := filepath.Rel(dir, path)
		if rel == "baseline.yaml" {
			return nil
		}
		f, err := loadFile(path, rel, b, opt)
		if err != nil {
			return err
		}
		files = append(files, f)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Code < files[j].Code })
	return files, nil
}

// expectedCode maps ca.yaml to CA and ca/qc.yaml to CA-QC.
func expectedCode(rel string) (string, bool) {
	parts := strings.Split(filepath.ToSlash(strings.TrimSuffix(rel, ".yaml")), "/")
	if len(parts) > 2 {
		return "", false
	}
	return strings.ToUpper(strings.Join(parts, "-")), true
}

func loadFile(path, rel string, b *Baseline, opt LoadOptions) (File, error) {
	var f File
	if err := decode(path, &f); err != nil {
		return f, err
	}
	f.Path = path
	want, ok := expectedCode(rel)
	switch {
	case !ok:
		return f, fmt.Errorf("%s: jurisdiction files go in <cc>.yaml or <cc>/<sub>.yaml", path)
	case !codeForm.MatchString(f.Code):
		return f, fmt.Errorf("%s: code %q must be an upper-case ISO 3166 code such as CA or CA-QC", path, f.Code)
	case f.Code != want:
		return f, fmt.Errorf("%s: code %s does not match the file path (want %s)", path, f.Code, want)
	case Territories().CountryName(f.Country(), "en") == "":
		return f, fmt.Errorf("%s: unknown country %s", path, f.Country())
	}
	if err := needText(path, "name", f.Name); err != nil {
		return f, err
	}
	seen := map[string]bool{}
	for i := range f.Rows {
		r := &f.Rows[i]
		what := "row " + r.ID
		switch {
		case b.byID[r.ID] == nil:
			return f, fmt.Errorf("%s: row %q is not in baseline.yaml", path, r.ID)
		case seen[r.ID]:
			return f, fmt.Errorf("%s: row %s appears twice", path, r.ID)
		case statusLabel[r.Status] == (Text{}):
			return f, fmt.Errorf("%s: row %s: status %q must be one of %s", path, r.ID, r.Status, strings.Join(Statuses, ", "))
		}
		seen[r.ID] = true
		if err := needText(path, what+" text", r.Text); err != nil {
			return f, err
		}
		if err := needSource(path, what+" source", r.Source); err != nil {
			return f, err
		}
		t, err := time.Parse("2006-01-02", r.LastChecked)
		if err != nil {
			return f, fmt.Errorf("%s: row %s: last_checked %q must be YYYY-MM-DD", path, r.ID, r.LastChecked)
		}
		if !opt.Today.IsZero() && t.After(opt.Today) {
			return f, fmt.Errorf("%s: row %s: last_checked %s is in the future", path, r.ID, r.LastChecked)
		}
		r.Checked = t
	}
	return f, nil
}

// Stale returns the rows last checked before today minus the given number of months.
// A row checked exactly that many months ago is not stale.
func Stale(files []File, today time.Time, months int) []StaleRow {
	cutoff := today.AddDate(0, -months, 0)
	var out []StaleRow
	for _, f := range files {
		for _, r := range f.Rows {
			if r.Checked.Before(cutoff) {
				out = append(out, StaleRow{f.Path, r.ID, r.Checked})
			}
		}
	}
	return out
}
