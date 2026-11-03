// SPDX-License-Identifier: Apache-2.0

// Package jurisdiction reads the comparison data of an FPSOT spec and generates its
// jurisdiction pages.
//
// A spec keeps jurisdictions/baseline.yaml (the requirement, the international
// baseline and the FPSOT default of each compared requirement) and one file per
// jurisdiction: jurisdictions/<cc>.yaml for a country (ISO 3166-1) and
// jurisdictions/<cc>/<sub>.yaml for a subdivision (ISO 3166-2). The format is
// defined by the LinkML model of the FPSOT documentation specification.
package jurisdiction

import "time"

// Text is a value in English and French.
type Text struct {
	EN string `yaml:"en"`
	FR string `yaml:"fr"`
}

// In returns the value in lang ("en" or "fr").
func (t Text) In(lang string) string {
	if lang == "fr" {
		return t.FR
	}
	return t.EN
}

// Source identifies the exact version of an outside document.
type Source struct {
	Title   string `yaml:"title"`
	Version string `yaml:"version"`
	Date    string `yaml:"date"`
	URL     string `yaml:"url"`
	Archive string `yaml:"archive"`
}

// BaselineRow is one compared requirement.
type BaselineRow struct {
	ID                  string `yaml:"id"`
	Topic               string `yaml:"topic"`
	Requirement         Text   `yaml:"requirement"`
	International       Text   `yaml:"international"`
	InternationalSource Source `yaml:"international_source"`
	FPSOT               Text   `yaml:"fpsot"`
}

// Baseline holds the topics and the rows every jurisdiction is compared against.
type Baseline struct {
	Topics map[string]Text `yaml:"topics"`
	Rows   []BaselineRow   `yaml:"rows"`
	byID   map[string]*BaselineRow
}

// Row is how one jurisdiction handles one baseline row.
type Row struct {
	ID          string    `yaml:"id"`
	Text        Text      `yaml:"text"`
	Status      string    `yaml:"status"`
	Source      Source    `yaml:"source"`
	LastChecked string    `yaml:"last_checked"`
	Checked     time.Time `yaml:"-"`
}

// File is one jurisdiction file.
type File struct {
	Path string `yaml:"-"`
	Code string `yaml:"code"`
	Name Text   `yaml:"name"`
	Rows []Row  `yaml:"rows"`
}

// Country returns the ISO 3166-1 part of the code.
func (f File) Country() string { return f.Code[:2] }

// IsSubdivision reports whether the file is for a subdivision.
func (f File) IsSubdivision() bool { return len(f.Code) > 2 }

// Statuses are the allowed row statuses, in display order.
var Statuses = []string{"same", "stricter", "looser", "not-covered"}

var statusLabel = map[string]Text{
	"same":        {"same", "identique"},
	"stricter":    {"stricter", "plus strict"},
	"looser":      {"looser", "moins strict"},
	"not-covered": {"not covered", "non couvert"},
}

// LoadOptions controls LoadDir.
type LoadOptions struct {
	// Today is the date a last_checked value may not be after.
	Today time.Time
}

// StaleRow is a row whose last check is too old.
type StaleRow struct {
	Path        string
	ID          string
	LastChecked time.Time
}
