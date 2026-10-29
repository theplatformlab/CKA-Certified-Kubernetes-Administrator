package main

// The question pool: exercises/<NN>-<name>/ and questions/<id>/.
// Each item directory has item.yaml (metadata), README.md (task, hints,
// solution) and lab.sh (setup/check, run through scripts/lab.sh).

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Curriculum domains with their exam weight in percent.
var Domains = []struct {
	Key, Name string
	Weight    int
}{
	{"troubleshooting", "Troubleshooting", 30},
	{"architecture", "Cluster Architecture", 25},
	{"networking", "Services & Networking", 20},
	{"workloads", "Workloads & Scheduling", 15},
	{"storage", "Storage", 10},
}

func domainName(key string) string {
	for _, d := range Domains {
		if d.Key == key {
			return d.Name
		}
	}
	return key
}

type Item struct {
	ID         string   `yaml:"-"`
	Dir        string   `yaml:"-"`
	Cluster    string   `yaml:"-"` // practice | ops | cni | runtime (LAB_CLUSTER in lab.sh)
	Exercise   bool     `yaml:"-"`
	Title      string   `yaml:"title"`
	Domain     string   `yaml:"domain"`
	Difficulty int      `yaml:"difficulty"`
	Minutes    int      `yaml:"minutes"`
	Weight     int      `yaml:"weight"`
	Modes      []string `yaml:"modes"`
	Namespaces []string `yaml:"namespaces"`
	Conflicts  []string `yaml:"conflicts"` // cluster-wide things the item changes or breaks
	Needs      []string `yaml:"needs"`     // things it relies on (never drawn with an item that breaks them)
	Order      string   `yaml:"order"` // "late": set up after the other items on its cluster
}

func (it *Item) Allows(mode string) bool {
	for _, m := range it.Modes {
		if m == mode {
			return true
		}
	}
	return false
}

func (it *Item) Label() string {
	if it.Exercise {
		return fmt.Sprintf("%s · %s", it.ID, it.Title)
	}
	return it.Title
}

var labClusterRe = regexp.MustCompile(`(?m)^LAB_CLUSTER=([a-z]+)`)

func LoadBank(root string) ([]*Item, error) {
	var items []*Item
	load := func(dir string, exercise bool) error {
		raw, err := os.ReadFile(filepath.Join(dir, "item.yaml"))
		if err != nil {
			return nil // not an item
		}
		it := &Item{Dir: dir, Exercise: exercise, Cluster: "practice"}
		if err := yaml.Unmarshal(raw, it); err != nil {
			return fmt.Errorf("%s: %w", dir, err)
		}
		if lab, err := os.ReadFile(filepath.Join(dir, "lab.sh")); err == nil {
			if m := labClusterRe.FindSubmatch(lab); m != nil {
				it.Cluster = string(m[1])
			}
		} else {
			return nil
		}
		base := filepath.Base(dir)
		if exercise {
			it.ID = "ex" + strings.SplitN(base, "-", 2)[0]
		} else {
			it.ID = base
		}
		if it.Minutes == 0 {
			it.Minutes = 10
		}
		if it.Weight == 0 {
			it.Weight = 5
		}
		if len(it.Modes) == 0 {
			it.Modes = []string{"practice", "exam"}
		}
		items = append(items, it)
		return nil
	}
	for _, sub := range []struct {
		glob     string
		exercise bool
	}{{"exercises/[0-9]*-*", true}, {"questions/*", false}} {
		dirs, _ := filepath.Glob(filepath.Join(root, sub.glob))
		for _, d := range dirs {
			if err := load(d, sub.exercise); err != nil {
				return nil, err
			}
		}
	}
	sort.Slice(items, func(i, j int) bool { return items[i].ID < items[j].ID })
	return items, nil
}

func findItem(items []*Item, id string) *Item {
	for _, it := range items {
		if it.ID == id {
			return it
		}
	}
	return nil
}

// ---- README parsing ------------------------------------------------------

type Doc struct {
	Question string
	Hints    []string
	Solution string
	Notes    string // "What tripped me up" / "Key Learning"
}

var (
	solutionDetailsRe = regexp.MustCompile(`(?s)<details>\s*<summary>(?:<b>)?Solution(?:</b>)?</summary>(.*?)</details>`)
	htmlTagRe         = regexp.MustCompile(`(?m)^\s*</?(details|summary)>.*$`)
	headingRe         = regexp.MustCompile(`(?m)^## (.+)$`)
)

func ParseReadme(md string) Doc {
	var doc Doc
	if m := solutionDetailsRe.FindStringSubmatch(md); m != nil {
		doc.Solution = strings.TrimSpace(m[1])
		md = solutionDetailsRe.ReplaceAllString(md, "")
	}
	locs := headingRe.FindAllStringSubmatchIndex(md, -1)
	pre := md
	if len(locs) > 0 {
		pre = md[:locs[0][0]]
	}
	var question []string
	question = append(question, cleanPreamble(pre))
	var notes []string
	for i, l := range locs {
		title := strings.TrimSpace(md[l[2]:l[3]])
		end := len(md)
		if i+1 < len(locs) {
			end = locs[i+1][0]
		}
		body := strings.TrimSpace(md[l[1]:end])
		lower := strings.ToLower(title)
		switch {
		case strings.HasPrefix(lower, "tasks"), lower == "context", lower == "setup", strings.HasPrefix(lower, "important"):
			question = append(question, "## "+title+"\n\n"+body)
		case lower == "hints":
			doc.Hints = parseHints(body)
		case lower == "solution":
			if doc.Solution == "" {
				doc.Solution = body
			}
		case lower == "what tripped me up", lower == "key learning":
			notes = append(notes, "## "+title+"\n\n"+body)
		}
	}
	doc.Question = strings.TrimSpace(strings.Join(question, "\n\n"))
	doc.Notes = strings.TrimSpace(strings.Join(notes, "\n\n"))
	return doc
}

func cleanPreamble(s string) string {
	var out []string
	for _, line := range strings.Split(s, "\n") {
		if strings.HasPrefix(line, "> Related:") {
			continue
		}
		out = append(out, line)
	}
	return strings.TrimSpace(strings.Join(out, "\n"))
}

// Hints are a bullet list (optionally wrapped in <details>); one hint per bullet.
func parseHints(body string) []string {
	body = htmlTagRe.ReplaceAllString(body, "")
	var hints []string
	var cur []string
	flush := func() {
		if len(cur) > 0 {
			hints = append(hints, strings.TrimSpace(strings.Join(cur, "\n")))
			cur = nil
		}
	}
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "- ") || strings.HasPrefix(line, "* ") {
			flush()
			cur = append(cur, strings.TrimSpace(line[2:]))
		} else if strings.TrimSpace(line) != "" && len(cur) > 0 {
			cur = append(cur, line)
		}
	}
	flush()
	if len(hints) == 0 {
		// No bullet list: every paragraph is a hint.
		for _, para := range strings.Split(body, "\n\n") {
			if p := strings.TrimSpace(para); p != "" {
				hints = append(hints, p)
			}
		}
	}
	return hints
}

// ---- Rendering -------------------------------------------------------------

var (
	labParenRe    = regexp.MustCompile(`\s*\([^()]*(?:lab\.sh|init-cluster\.sh)[^()]*\)`)
	runSetupRe    = regexp.MustCompile("Run `\\./scripts/lab\\.sh setup [0-9a-z-]+` first[.,]?\\s*")
	validateWithR = regexp.MustCompile("(?i),? *and validate with `\\./scripts/lab\\.sh check [0-9a-z-]+`")
	labRefRe      = regexp.MustCompile("`\\./scripts/lab\\.sh (setup|check) [0-9a-z-]+`")
	placeholderRe = regexp.MustCompile(`\{\{([A-Z][A-Z0-9_]*)\}\}`)
)

// stripLabHints removes the lab.sh instructions from exercise texts: inside
// ./cka the setup has already run and checking is a key press.
func stripLabHints(s string) string {
	var out []string
	for _, line := range strings.Split(s, "\n") {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "Validate with `./scripts/lab.sh") || strings.HasPrefix(t, "./scripts/lab.sh ") {
			continue
		}
		line = labParenRe.ReplaceAllString(line, "")
		line = runSetupRe.ReplaceAllString(line, "")
		line = validateWithR.ReplaceAllString(line, "")
		line = labRefRe.ReplaceAllStringFunc(line, func(m string) string {
			if strings.Contains(m, " setup ") {
				return "the setup"
			}
			return "the check"
		})
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}

// Render substitutes {{KEY}} placeholders and, for exercises, the default
// cluster names written in the text (cka-practice, cka-ops, ...).
func Render(s string, vars map[string]string, clusters map[string]string) string {
	s = placeholderRe.ReplaceAllStringFunc(s, func(m string) string {
		key := m[2 : len(m)-2]
		if v, ok := vars[key]; ok {
			return v
		}
		return m
	})
	for profile, def := range defaultClusters {
		if actual := clusters[profile]; actual != "" && actual != def {
			s = regexp.MustCompile(`\b`+regexp.QuoteMeta(def)+`\b`).ReplaceAllString(s, actual)
		}
	}
	return s
}

var defaultClusters = map[string]string{
	"practice": "cka-practice",
	"ops":      "cka-ops",
	"cni":      "cka-cni",
	"runtime":  "cka-runtime",
}

func (it *Item) Doc() (Doc, error) {
	raw, err := os.ReadFile(filepath.Join(it.Dir, "README.md"))
	if err != nil {
		return Doc{}, err
	}
	doc := ParseReadme(string(raw))
	if it.Exercise {
		doc.Question = stripLabHints(doc.Question)
		doc.Solution = stripLabHints(doc.Solution)
	}
	return doc, nil
}
