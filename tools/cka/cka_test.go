package main

import (
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseReadmeExercise(t *testing.T) {
	md := "# Exercise 99 — Demo\n\n> Related: [x](y)\n\nIntro.\n\n## Tasks\n\nWork in namespace `ex` (`./scripts/lab.sh setup 99` creates it).\n\n1. Do it\n\nValidate with `./scripts/lab.sh check 99`.\n\n" +
		"## Hints\n\n<details>\n<summary>Stuck?</summary>\n\n- first\n- second\n  continued\n\n</details>\n\n## What tripped me up\n\n> trap\n\n## Verify\n\nk get pods\n\n## Cleanup\n\nx\n\n<details>\n<summary>Solution</summary>\n\nk apply\n\n</details>\n"
	doc := ParseReadme(md)
	q := stripLabHints(doc.Question)
	if strings.Contains(q, "lab.sh") || strings.Contains(q, "Related") || strings.Contains(q, "k get pods") {
		t.Errorf("question not cleaned:\n%s", q)
	}
	if !strings.Contains(q, "Work in namespace `ex`.") {
		t.Errorf("parenthetical not removed:\n%s", q)
	}
	if len(doc.Hints) != 2 || !strings.Contains(doc.Hints[1], "continued") {
		t.Errorf("hints: %#v", doc.Hints)
	}
	if doc.Solution != "k apply" || !strings.Contains(doc.Notes, "trap") {
		t.Errorf("solution %q notes %q", doc.Solution, doc.Notes)
	}
}

func TestRender(t *testing.T) {
	out := Render("use {{CONTEXT}} on cka-practice-worker2 and cka-ops, keep {{UNKNOWN}}",
		map[string]string{"CONTEXT": "kind-cka-exam"},
		map[string]string{"practice": "cka-exam", "ops": "cka-exam-ops"})
	want := "use kind-cka-exam on cka-exam-worker2 and cka-exam-ops, keep {{UNKNOWN}}"
	if out != want {
		t.Errorf("got %q", out)
	}
}

func testItems() []*Item {
	var items []*Item
	add := func(id, domain string, minutes int, ns []string, conflicts []string, cluster string) {
		items = append(items, &Item{ID: id, Domain: domain, Minutes: minutes, Weight: minutes, Namespaces: ns,
			Conflicts: conflicts, Cluster: cluster, Modes: []string{"practice", "exam"}})
	}
	for i, d := range Domains {
		for j := 0; j < 6; j++ {
			id := d.Key + string(rune('a'+j))
			add(id, d.Key, 8, []string{id}, nil, "practice")
		}
		_ = i
	}
	add("conflict-1", "troubleshooting", 8, []string{"x1"}, []string{"apiserver"}, "ops")
	add("conflict-2", "troubleshooting", 8, []string{"x2"}, []string{"apiserver"}, "ops")
	add("shared-ns-1", "workloads", 8, []string{"same"}, nil, "practice")
	add("shared-ns-2", "workloads", 8, []string{"same"}, nil, "practice")
	add("topic-1", "networking", 8, []string{"t1"}, nil, "practice")
	add("topic-2", "networking", 8, []string{"t2"}, nil, "practice")
	items[len(items)-2].Topic, items[len(items)-1].Topic = "same-topic", "same-topic"
	add("special-1", "architecture", 8, []string{"s1"}, nil, "ha")
	add("special-2", "architecture", 8, []string{"s2"}, nil, "cni")
	add("own-1", "troubleshooting", 8, []string{"o1"}, []string{"apiserver"}, "ops")
	add("own-2", "troubleshooting", 8, []string{"o2"}, []string{"apiserver"}, "ops")
	items[len(items)-2].OwnCluster, items[len(items)-1].OwnCluster = true, true
	return items
}

func noParams(*Item, int64) (map[string]string, error) { return map[string]string{}, nil }

func TestGenerateExam(t *testing.T) {
	items := testItems()
	for seed := int64(0); seed < 50; seed++ {
		picks, err := Generate(items, map[string]ItemStat{}, GenOptions{Mode: "exam", Minutes: 120, Count: 17, Seed: seed}, noParams)
		if err != nil {
			t.Fatal(err)
		}
		perDomain := map[string]int{}
		ids := map[string]bool{}
		for _, p := range picks {
			perDomain[p.Item.Domain] += p.Item.Minutes
			ids[p.Item.ID] = true
		}
		if ids["conflict-1"] && ids["conflict-2"] {
			t.Errorf("seed %d: conflicting items together", seed)
		}
		if ids["shared-ns-1"] && ids["shared-ns-2"] {
			t.Errorf("seed %d: namespace collision", seed)
		}
		if len(picks) != 17 {
			t.Errorf("seed %d: %d questions", seed, len(picks))
		}
		if ids["topic-1"] && ids["topic-2"] {
			t.Errorf("seed %d: two items of one topic", seed)
		}
		if extra, _ := extraClusters(pickItems(picks)); extra > 1 {
			t.Errorf("seed %d: %d clusters besides practice and ops", seed, extra)
		}
		if perDomain["troubleshooting"] < perDomain["storage"] {
			t.Errorf("seed %d: weighting off: %v", seed, perDomain)
		}
	}
}

func TestClusterKeys(t *testing.T) {
	ops := &Item{Cluster: "ops"}
	own := &Item{Cluster: "ops", OwnCluster: true}
	cni := &Item{Cluster: "cni", OwnCluster: true}
	for _, c := range []struct {
		items []*Item
		want  string
	}{
		{[]*Item{own}, "ops"},
		{[]*Item{own, cni}, "ops cni"},
		{[]*Item{ops, own}, "ops ops2"},
		{[]*Item{own, ops, own}, "ops2 ops ops3"},
		{[]*Item{own, own}, "ops ops2"},
	} {
		if got := strings.Join(ClusterKeys(c.items), " "); got != c.want {
			t.Errorf("got %q, want %q", got, c.want)
		}
	}
	// Tags don't keep an own_cluster item away from the others.
	if conflicts(Pick{Item: &Item{Cluster: "ops", Conflicts: []string{"x"}, OwnCluster: true}}, Pick{Item: &Item{Cluster: "ops", Needs: []string{"x"}}}) {
		t.Error("own_cluster item conflicts")
	}
}

func TestGeneratePrefersNewThenFailed(t *testing.T) {
	items := testItems()
	stats := map[string]ItemStat{}
	now := time.Now()
	for _, it := range items {
		if it.Domain == "storage" {
			stats[it.ID] = ItemStat{Attempts: 1, Passes: 1, Last: now, LastPass: true}
		}
	}
	stats["storagea"] = ItemStat{Attempts: 1, Last: now, LastPass: false}
	delete(stats, "storageb") // the only new storage item
	picks, err := Generate(items, stats, GenOptions{Mode: "practice", Domain: "storage", Count: 2, Seed: 1}, noParams)
	if err != nil {
		t.Fatal(err)
	}
	if picks[0].Item.ID != "storageb" || picks[1].Item.ID != "storagea" {
		t.Errorf("order: %s, %s", picks[0].Item.ID, picks[1].Item.ID)
	}
}

// The real pool must load and every item must have a task and a solution.
func TestPool(t *testing.T) {
	repoRoot = filepath.Join("..", "..")
	items, err := LoadBank(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) < 60 {
		t.Fatalf("only %d items", len(items))
	}
	valid := map[string]bool{}
	for _, d := range Domains {
		valid[d.Key] = true
	}
	for _, it := range items {
		if !valid[it.Domain] {
			t.Errorf("%s: unknown domain %q", it.ID, it.Domain)
		}
		doc, err := it.Doc()
		if err != nil {
			t.Errorf("%s: %v", it.ID, err)
			continue
		}
		if len(doc.Question) < 50 || len(doc.Solution) < 20 {
			t.Errorf("%s: question %d chars, solution %d chars", it.ID, len(doc.Question), len(doc.Solution))
		}
		if len(doc.Hints) == 0 {
			t.Errorf("%s: no hints", it.ID)
		}
		if it.Topic == "" {
			t.Errorf("%s: no topic", it.ID)
		}
		if it.Allows("exam") && it.ExamMins == 0 {
			t.Errorf("%s: exam item without exam_minutes", it.ID)
		}
		if areas := domainAreas[it.Domain]; len(areas) > 0 {
			found := false
			for _, a := range areas {
				found = found || a == it.Area
			}
			if !found {
				t.Errorf("%s: area %q is not one of %v", it.ID, it.Area, areas)
			}
		}
	}
}

func TestApplyBaseline(t *testing.T) {
	si := &SessionItem{Baseline: []string{"cannot delete"}, Checks: []CheckResult{
		{Pass: true, Desc: "cannot delete"}, {Pass: false, Desc: "role exists"}}}
	si.ApplyBaseline()
	if si.Passed() != 0 {
		t.Errorf("untouched item kept %d points", si.Passed())
	}
	si = &SessionItem{Baseline: []string{"cannot delete"}, Checks: []CheckResult{
		{Pass: true, Desc: "cannot delete"}, {Pass: true, Desc: "role exists"}}}
	si.ApplyBaseline()
	if si.Passed() != 2 {
		t.Errorf("attempted item lost points: %d", si.Passed())
	}
}

func TestExamView(t *testing.T) {
	q := "# Exercise 32 — Troubleshoot\n\n> **Medium** | ~15 min\n\nClients fail.\n\n## Tasks\n\n> keep me\n1. fix"
	out := ExamView(q, 4)
	if !strings.HasPrefix(out, "# Question 4\n") || strings.Contains(out, "Medium") || strings.Contains(out, "Exercise") {
		t.Errorf("not hidden:\n%s", out)
	}
	if !strings.Contains(out, "> keep me") || !strings.Contains(out, "Clients fail.") {
		t.Errorf("too much removed:\n%s", out)
	}
}

func TestDomainQuotas(t *testing.T) {
	q := domainQuotas(17)
	sum := 0
	for _, v := range q {
		sum += v
	}
	if sum != 17 || q["troubleshooting"] != 5 || q["storage"] != 2 {
		t.Errorf("quotas %v", q)
	}
}

func TestPracticeAllDomainsWeighted(t *testing.T) {
	items := testItems()
	picks, err := Generate(items, map[string]ItemStat{}, GenOptions{Mode: "practice", Count: 10, Seed: 3}, noParams)
	if err != nil {
		t.Fatal(err)
	}
	per := map[string]int{}
	for _, p := range picks {
		per[p.Item.Domain]++
	}
	if len(picks) != 10 || per["troubleshooting"] != 3 || per["storage"] != 1 {
		t.Errorf("distribution %v", per)
	}
}

// With 5 troubleshooting slots, every area is covered.
func TestExamTroubleshootingAreas(t *testing.T) {
	repoRoot = filepath.Join("..", "..")
	items, err := LoadBank(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	for seed := int64(0); seed < 200; seed++ {
		picks, err := Generate(items, map[string]ItemStat{}, GenOptions{Mode: "exam", Minutes: 120, Count: 17, Seed: seed}, noParams)
		if err != nil {
			t.Fatal(err)
		}
		areas := map[string]bool{}
		for _, p := range picks {
			if p.Item.Domain == "troubleshooting" {
				areas[p.Item.Area] = true
			}
		}
		for _, a := range domainAreas["troubleshooting"] {
			if !areas[a] {
				t.Errorf("seed %d: no troubleshooting item for %s (%v)", seed, a, areas)
			}
		}
	}
}

// Exam namespaces of exercises must not collide with any namespace in the pool.
func TestExamNamespacesUnique(t *testing.T) {
	repoRoot = filepath.Join("..", "..")
	items, err := LoadBank(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	owner := map[string]string{}
	claim := func(ns, id string) {
		if prev, ok := owner[ns]; ok && prev != id {
			t.Errorf("namespace %q used by %s and %s", ns, prev, id)
		}
		owner[ns] = id
	}
	for _, it := range items {
		for _, ns := range it.Namespaces {
			if it.Exercise && exerciseNSRe.MatchString(ns) {
				continue // replaced in exams, practice-only otherwise
			}
			if !strings.Contains(ns, "{{") {
				claim(ns, it.ID)
			}
		}
		if ns := examNamespace(it); ns != "" {
			claim(ns, it.ID)
			for _, extra := range it.Namespaces {
				if exerciseNSRe.MatchString(extra) {
					claim(exerciseNSRe.ReplaceAllString(extra, ns), it.ID)
				}
			}
		}
	}
}

func TestRenderExamNamespace(t *testing.T) {
	out := Render("ns exercise-20 and exercise-20-baseline, files in ~/cka-lab/ex20/x",
		map[string]string{"@NS": "secured", "@ID": "ex20", "WORKDIR": "~/cka-lab/q03"}, nil)
	if out != "ns secured and secured-baseline, files in ~/cka-lab/q03/x" {
		t.Errorf("got %q", out)
	}
}
