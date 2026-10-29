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
	add("special-1", "architecture", 8, []string{"s1"}, nil, "ha")
	add("special-2", "architecture", 8, []string{"s2"}, nil, "cni")
	return items
}

func noParams(*Item, int64) (map[string]string, error) { return map[string]string{}, nil }

func TestGenerateExam(t *testing.T) {
	items := testItems()
	for seed := int64(0); seed < 50; seed++ {
		picks, err := Generate(items, map[string]ItemStat{}, GenOptions{Mode: "exam", Minutes: 120, Seed: seed}, noParams)
		if err != nil {
			t.Fatal(err)
		}
		perDomain := map[string]int{}
		ids := map[string]bool{}
		special := 0
		for _, p := range picks {
			perDomain[p.Item.Domain] += p.Item.Minutes
			ids[p.Item.ID] = true
			if specialClusters[p.Item.Cluster] {
				special++
			}
		}
		if ids["conflict-1"] && ids["conflict-2"] {
			t.Errorf("seed %d: conflicting items together", seed)
		}
		if ids["shared-ns-1"] && ids["shared-ns-2"] {
			t.Errorf("seed %d: namespace collision", seed)
		}
		if special > 1 {
			t.Errorf("seed %d: %d special-cluster items", seed, special)
		}
		if perDomain["troubleshooting"] < perDomain["storage"] {
			t.Errorf("seed %d: weighting off: %v", seed, perDomain)
		}
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
