package main

// The question pool: questions/<id>/.
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

// The certifications and their curricula. Every domain lists its areas
// (curriculum bullets, in the order a generated session covers them); every
// item names the area(s) it trains, so one item can belong to several exams
// (a NetworkPolicy item counts for CKA, CKAD and CKS) without duplicates.
type Domain struct {
	Key, Name string
	Weight    int // percent of the exam
	Areas     []string
}

type Exam struct {
	Key, Name, Title string
	Domains          []Domain
}

var Exams = []*Exam{
	{"cka", "CKA", "Certified Kubernetes Administrator", []Domain{
		{"troubleshooting", "Troubleshooting", 30, []string{"cluster-components", "nodes", "networking", "observability", "applications"}},
		{"architecture", "Cluster Architecture", 25, []string{"cluster-lifecycle", "rbac", "helm-kustomize", "crds-operators", "extensions"}},
		{"networking", "Services & Networking", 20, []string{"services", "network-policies", "ingress-gateway", "dns"}},
		{"workloads", "Workloads & Scheduling", 15, []string{"rollouts", "scheduling", "configuration", "workload-controllers", "resources", "pods", "pod-security", "autoscaling"}},
		{"storage", "Storage", 10, []string{"volumes", "storage-classes"}},
	}},
	{"ckad", "CKAD", "Certified Kubernetes Application Developer", []Domain{
		{"environment", "Environment, Configuration & Security", 25, []string{"configuration", "pod-security", "resources", "rbac", "crds-operators"}},
		{"design", "Application Design & Build", 20, []string{"workload-controllers", "pods", "volumes", "container-images"}},
		{"deployment", "Application Deployment", 20, []string{"rollouts", "helm-kustomize", "autoscaling"}},
		{"services", "Services & Networking", 20, []string{"services", "network-policies", "ingress-gateway", "networking"}},
		{"observability", "Observability & Maintenance", 15, []string{"probes", "observability", "applications", "api-deprecations"}},
	}},
	{"cks", "CKS", "Certified Kubernetes Security Specialist", []Domain{
		{"microservices", "Minimize Microservice Vulnerabilities", 20, []string{"pod-security", "secrets-management", "isolation", "pod-encryption"}},
		{"supply-chain", "Supply Chain Security", 20, []string{"static-analysis", "image-policy", "image-footprint", "sbom"}},
		{"runtime", "Monitoring, Logging & Runtime Security", 20, []string{"runtime-detection", "audit-logs", "immutability"}},
		{"cluster-setup", "Cluster Setup", 15, []string{"network-policies", "cis-benchmark", "ingress-tls", "node-metadata", "binary-verification"}},
		{"hardening", "Cluster Hardening", 15, []string{"rbac", "serviceaccount-security", "api-access", "cluster-upgrade"}},
		{"system", "System Hardening", 10, []string{"kernel-hardening", "host-os", "network-access"}},
	}},
}

func ExamByKey(key string) *Exam {
	for _, ex := range Exams {
		if ex.Key == key {
			return ex
		}
	}
	return Exams[0] // sessions from before the exam choice are CKA
}

func (ex *Exam) domain(key string) *Domain {
	for i := range ex.Domains {
		if ex.Domains[i].Key == key {
			return &ex.Domains[i]
		}
	}
	return nil
}

func (ex *Exam) DomainName(key string) string {
	if d := ex.domain(key); d != nil {
		return d.Name
	}
	return key
}

// place: the domain and area an item counts for in this exam ("" if it is
// not part of the exam). Its first area that the curriculum lists wins.
func (ex *Exam) place(it *Item) (domain, area string) {
	if len(it.Exams) > 0 && !contains(it.Exams, ex.Key) {
		return "", ""
	}
	for _, a := range append([]string{it.Area}, it.Areas...) {
		for _, d := range ex.Domains {
			if contains(d.Areas, a) {
				return d.Key, a
			}
		}
	}
	return "", ""
}

// Pool: the exam's items, as copies whose Domain and Area are the exam's.
func (ex *Exam) Pool(items []*Item) []*Item {
	var out []*Item
	for _, it := range items {
		if d, a := ex.place(it); d != "" {
			c := *it
			c.Domain, c.Area = d, a
			out = append(out, &c)
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

var areaNames = map[string]string{
	"cluster-components":      "Cluster components",
	"nodes":                   "Nodes",
	"networking":              "Service & network troubleshooting",
	"observability":           "Logs, monitoring & debugging",
	"applications":            "Application failures",
	"cluster-lifecycle":       "kubeadm, etcd & cluster lifecycle",
	"rbac":                    "RBAC & cluster access",
	"helm-kustomize":          "Helm & Kustomize",
	"crds-operators":          "CRDs & operators",
	"extensions":              "CNI, CSI & CRI",
	"services":                "Services",
	"network-policies":        "NetworkPolicies",
	"ingress-gateway":         "Ingress & Gateway API",
	"dns":                     "CoreDNS",
	"rollouts":                "Deployments, rollouts & strategies",
	"workload-controllers":    "DaemonSets, StatefulSets, Jobs",
	"scheduling":              "Scheduling",
	"resources":               "Requests, limits & quotas",
	"configuration":           "ConfigMaps & Secrets",
	"pods":                    "Pod design (multi-container, init, static)",
	"pod-security":            "Pod security & SecurityContexts",
	"autoscaling":             "Autoscaling",
	"volumes":                 "Volumes, PVs & claims",
	"storage-classes":         "StorageClasses & provisioning",
	"container-images":        "Container images",
	"probes":                  "Probes & health checks",
	"api-deprecations":        "API deprecations",
	"secrets-management":      "Secrets management",
	"isolation":               "Isolation & sandboxed containers",
	"pod-encryption":          "Pod-to-pod encryption",
	"static-analysis":         "Static analysis & image scanning",
	"image-policy":            "Permitted registries & admission",
	"image-footprint":         "Base image footprint",
	"sbom":                    "SBOM & supply chain",
	"runtime-detection":       "Runtime threat detection (Falco)",
	"audit-logs":              "Audit logs",
	"immutability":            "Immutable containers",
	"cis-benchmark":           "CIS benchmark",
	"ingress-tls":             "Ingress with TLS",
	"node-metadata":           "Node metadata & endpoints",
	"binary-verification":     "Verify platform binaries",
	"serviceaccount-security": "ServiceAccount security",
	"api-access":              "Restrict API access",
	"cluster-upgrade":         "Upgrades",
	"kernel-hardening":        "AppArmor & seccomp",
	"host-os":                 "Host OS footprint & least privilege",
	"network-access":          "External network access",
}

func areaName(key string) string {
	if n := areaNames[key]; n != "" {
		return n
	}
	return key
}

type Item struct {
	ID         string   `yaml:"-"`
	Dir        string   `yaml:"-"`
	Cluster    string   `yaml:"-"` // practice | ops | cni | runtime (LAB_CLUSTER in lab.sh)
	Title      string   `yaml:"title"`
	Topic      string   `yaml:"topic"` // at most one item per topic in a generated session
	Domain     string   `yaml:"-"`     // set by Exam.Pool: the item's domain in that exam
	Area       string   `yaml:"area"`  // the curriculum area it trains (see Exams)
	Areas      []string `yaml:"areas"` // further areas, e.g. of another exam's curriculum
	Exams      []string `yaml:"exams"` // only these exams (default: every exam listing one of its areas)
	Difficulty int      `yaml:"difficulty"`
	Minutes    int      `yaml:"minutes"`      // recommended time when practising
	ExamMins   int      `yaml:"exam_minutes"` // realistic time at exam pace
	Weight     int      `yaml:"weight"`
	Modes      []string `yaml:"modes"`
	Namespaces []string `yaml:"namespaces"`
	Conflicts  []string `yaml:"conflicts"`   // cluster-wide things the item changes or breaks
	Needs      []string `yaml:"needs"`       // things it relies on (never drawn with an item that breaks them)
	OwnCluster bool     `yaml:"own_cluster"` // its setup breaks the cluster: never shares it with other items
}

func (it *Item) Allows(mode string) bool {
	for _, m := range it.Modes {
		if m == mode {
			return true
		}
	}
	return false
}

func (it *Item) Label() string { return it.Title }

var labClusterRe = regexp.MustCompile(`(?m)^LAB_CLUSTER=([a-z]+)`)

func LoadBank(root string) ([]*Item, error) {
	var items []*Item
	load := func(dir string) error {
		raw, err := os.ReadFile(filepath.Join(dir, "item.yaml"))
		if err != nil {
			return nil // not an item
		}
		it := &Item{Dir: dir, Cluster: "practice", ID: filepath.Base(dir)}
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
	dirs, _ := filepath.Glob(filepath.Join(root, "questions", "*"))
	for _, d := range dirs {
		if err := load(d); err != nil {
			return nil, err
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
	Notes    string // "Pitfalls"
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
		case strings.HasPrefix(lower, "tasks"), lower == "context", lower == "setup", lower == "current state", strings.HasPrefix(lower, "important"):
			question = append(question, "## "+title+"\n\n"+body)
		case lower == "hints":
			doc.Hints = parseHints(body)
		case lower == "solution":
			if doc.Solution == "" {
				doc.Solution = body
			}
		case lower == "pitfalls":
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
		if strings.HasPrefix(line, "> Related:") || strings.TrimSpace(line) == ">" {
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

// Render substitutes {{KEY}} placeholders and the default cluster names
// written in the text (cka-practice, cka-ops, ...).
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
	"ha":       "cka-ha",
	"cks":      "cka-cks",
}

func (it *Item) Doc() (Doc, error) {
	raw, err := os.ReadFile(filepath.Join(it.Dir, "README.md"))
	if err != nil {
		return Doc{}, err
	}
	doc := ParseReadme(string(raw))
	// Like on the exam, every task starts with the context to switch to.
	if !strings.Contains(doc.Question, "use-context") {
		title, rest, _ := strings.Cut(doc.Question, "\n")
		if strings.HasPrefix(title, "# ") {
			doc.Question = title + "\n\n**Context:** `kubectl config use-context {{CONTEXT}}`\n" + rest
		} else {
			doc.Question = "**Context:** `kubectl config use-context {{CONTEXT}}`\n\n" + doc.Question
		}
	}
	return doc, nil
}

// ExamView hides what the real exam doesn't show: the item's title (the
// question is just "Question N") and the notes under it (difficulty,
// domain, "supplemental" remarks).
func ExamView(question string, n int) string {
	lines := strings.Split(question, "\n")
	var out []string
	inPreamble := true
	for i, line := range lines {
		if i == 0 && strings.HasPrefix(line, "# ") {
			out = append(out, fmt.Sprintf("# Question %d", n))
			continue
		}
		if strings.HasPrefix(line, "## ") {
			inPreamble = false
		}
		if inPreamble && strings.HasPrefix(line, ">") {
			continue
		}
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}
