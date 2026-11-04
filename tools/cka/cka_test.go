package main

import (
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseReadme(t *testing.T) {
	md := "# Demo\n\n> Related: [x](y)\n\nIntro.\n\n## Hints\n\n<details>\n<summary>Stuck?</summary>\n\n- first\n- second\n  continued\n\n</details>\n\n" +
		"## Solution\n\nk apply\n\n## Pitfalls\n\n> trap\n"
	doc := ParseReadme(md)
	if strings.Contains(doc.Question, "Related") || !strings.Contains(doc.Question, "Intro.") {
		t.Errorf("question:\n%s", doc.Question)
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
		items = append(items, &Item{ID: id, Area: Exams[0].domain(domain).Areas[0], Minutes: minutes, Weight: minutes, Namespaces: ns,
			Conflicts: conflicts, Cluster: cluster, Modes: []string{"practice", "exam"}})
	}
	for i, d := range Exams[0].Domains {
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
		if strings.HasPrefix(it.ID, "storage") {
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
	for _, it := range items {
		for _, a := range append([]string{it.Area}, it.Areas...) {
			if areaNames[a] == "" {
				t.Errorf("%s: unknown area %q", it.ID, a)
			}
		}
		inExam := false
		for _, ex := range Exams {
			d, _ := ex.place(it)
			inExam = inExam || d != ""
		}
		if !inExam {
			t.Errorf("%s: area %q is in no exam's curriculum", it.ID, it.Area)
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
	}
}

// Every area has a name and appears at most once per curriculum; weights add up.
func TestCurricula(t *testing.T) {
	for _, ex := range Exams {
		seen, weight := map[string]bool{}, 0
		for _, d := range ex.Domains {
			weight += d.Weight
			for _, a := range d.Areas {
				if areaNames[a] == "" {
					t.Errorf("%s: area %q has no name", ex.Name, a)
				}
				if seen[a] {
					t.Errorf("%s: area %q in two domains", ex.Name, a)
				}
				seen[a] = true
			}
		}
		if weight != 100 {
			t.Errorf("%s: weights add up to %d", ex.Name, weight)
		}
	}
}

// One item can count for several exams, in each with that exam's domain.
func TestExamPools(t *testing.T) {
	repoRoot = filepath.Join("..", "..")
	items, err := LoadBank(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	place := map[string]string{}
	for _, ex := range Exams {
		for _, it := range ex.Pool(items) {
			if it.ID == "netpol-three-tier" {
				place[ex.Key] = it.Domain
			}
		}
		if _, err := Generate(items, map[string]ItemStat{}, GenOptions{Exam: ex.Key, Mode: "exam", Minutes: 120, Count: 17, Seed: 1}, noParams); err != nil {
			t.Errorf("%s exam: %v", ex.Name, err)
		}
	}
	if place["cka"] != "networking" || place["ckad"] != "services" || place["cks"] != "cluster-setup" {
		t.Errorf("netpol-three-tier placed %v", place)
	}
}

func TestExamView(t *testing.T) {
	q := "# Troubleshoot\n\n> **Medium** | ~15 min\n\nClients fail.\n\n## Tasks\n\n> keep me\n1. fix"
	out := ExamView(q, 4)
	if !strings.HasPrefix(out, "# Question 4\n") || strings.Contains(out, "Medium") || strings.Contains(out, "Troubleshoot") {
		t.Errorf("not hidden:\n%s", out)
	}
	if !strings.Contains(out, "> keep me") || !strings.Contains(out, "Clients fail.") {
		t.Errorf("too much removed:\n%s", out)
	}
}

func TestDomainQuotas(t *testing.T) {
	q := domainQuotas(Exams[0], 17)
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
		for _, a := range Exams[0].domain("troubleshooting").Areas {
			if !areas[a] {
				t.Errorf("seed %d: no troubleshooting item for %s (%v)", seed, a, areas)
			}
		}
	}
}

func TestNextBackgroundCheck(t *testing.T) {
	now := time.Now()
	ago := func(d time.Duration) time.Time { return now.Add(-d) }
	s := &Session{Items: []*SessionItem{
		{CheckedAt: ago(time.Minute), SeenAt: ago(2 * time.Minute)},      // graded after the last visit
		{CheckedAt: ago(3 * time.Minute), SeenAt: ago(time.Minute)},      // left after its check: due
		{CheckedAt: ago(30 * time.Second), SeenAt: now},                  // on screen
		{CheckedAt: ago(4 * time.Minute), SeenAt: ago(10 * time.Minute)}, // old, but not stale yet
	}}
	if got := nextBackgroundCheck(s, 2, now); got != 1 {
		t.Errorf("got %d, want the question left since its check (1)", got)
	}
	s.Items[1].CheckedAt = now
	if got := nextBackgroundCheck(s, 2, now); got != -1 {
		t.Errorf("got %d, want none due", got)
	}
	s.Items[2].CheckedAt = ago(3 * time.Minute)
	if got := nextBackgroundCheck(s, 2, now); got != 2 {
		t.Errorf("got %d, want the question on screen (2)", got)
	}
	s.Items[2].CheckedAt = now
	s.Items[3].CheckedAt = ago(6 * time.Minute)
	if got := nextBackgroundCheck(s, 2, now); got != 3 {
		t.Errorf("got %d, want the stale question (3)", got)
	}
	if (&SessionItem{}).NeedsRecheck() != true {
		t.Error("an unchecked item must be checked")
	}
}

// A practice session limited to an area only draws from that area.
func TestGeneratePracticeArea(t *testing.T) {
	repoRoot = filepath.Join("..", "..")
	items, err := LoadBank(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	picks, err := Generate(items, map[string]ItemStat{}, GenOptions{Mode: "practice", Domain: "architecture", Area: "helm-kustomize", Count: 10, Seed: 1}, noParams)
	if err != nil {
		t.Fatal(err)
	}
	if len(picks) < 2 {
		t.Errorf("only %d helm/kustomize items", len(picks))
	}
	for _, p := range picks {
		if p.Item.Area != "helm-kustomize" {
			t.Errorf("%s: area %s", p.Item.ID, p.Item.Area)
		}
	}
}

// Every namespace belongs to one item, so no two questions of a session share one.
func TestNamespacesUnique(t *testing.T) {
	repoRoot = filepath.Join("..", "..")
	items, err := LoadBank(repoRoot)
	if err != nil {
		t.Fatal(err)
	}
	owner := map[string]string{}
	for _, it := range items {
		for _, ns := range it.Namespaces {
			if strings.Contains(ns, "{{") || ns == "default" {
				continue
			}
			if prev, ok := owner[ns]; ok && prev != it.ID {
				t.Errorf("namespace %q used by %s and %s", ns, prev, it.ID)
			}
			owner[ns] = it.ID
		}
	}
}
