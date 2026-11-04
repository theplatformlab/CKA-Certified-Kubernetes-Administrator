package main

// Session generation: picks items from the pool.
//   exam:     curriculum-weighted by domain, within a time budget
//   practice: a number of items, optionally from one domain
// Within a domain, never-attempted items come first, then items whose last
// attempt failed, then passed ones (least recently practised first).
// A session never contains two items of the same topic.

import (
	"fmt"
	"math/rand"
	"sort"
	"strings"
)

type GenOptions struct {
	Exam    string // cka | ckad | cks ("" = cka)
	Mode    string // exam | practice
	Minutes int    // exam duration
	Domain  string // practice: "" = all
	Area    string // practice: "" = the whole domain
	Count   int    // number of items (practice) / questions (exam)
	Only    []string
	Seed    int64
}

type Pick struct {
	Item       *Item
	Seed       int64
	Params     map[string]string
	Namespaces []string
}

// ParamFunc evaluates an item's lab_params for a seed.
type ParamFunc func(it *Item, seed int64) (map[string]string, error)

// ClusterKeys gives each item the session cluster it runs on (a key of
// Session.Clusters): its profile, or for an own_cluster item that would share
// the profile with other items, a separate cluster ("ops2", "ops3", ...), so
// the API server or kubelet it breaks never gets in their way.
func ClusterKeys(items []*Item) []string {
	used := map[string]int{}
	for _, it := range items {
		if !it.OwnCluster {
			used[it.Cluster] = 1
		}
	}
	keys := make([]string, len(items))
	for i, it := range items {
		keys[i] = it.Cluster
		if it.OwnCluster {
			used[it.Cluster]++
			if used[it.Cluster] > 1 {
				keys[i] = fmt.Sprintf("%s%d", it.Cluster, used[it.Cluster])
			}
		}
	}
	return keys
}

// profileOf: the cluster profile of a session cluster key ("ops2" -> "ops").
func profileOf(key string) string { return strings.TrimRight(key, "0123456789") }

// baseClusters: the clusters a session of the exam normally uses anyway.
var baseClusters = map[string]bool{"practice": true, "ops": true, "cks": true}

// extraClusters counts the clusters besides the base ones, and the extra
// copies of a profile (own_cluster items), that the items need.
func extraClusters(items []*Item) (extra, copies int) {
	seen := map[string]bool{}
	for i, k := range ClusterKeys(items) {
		if !baseClusters[k] && !seen[k] {
			seen[k] = true
			extra++
		}
		if k != items[i].Cluster {
			copies++
		}
	}
	return extra, copies
}

func Generate(items []*Item, stats map[string]ItemStat, opt GenOptions, params ParamFunc) ([]Pick, error) {
	rng := rand.New(rand.NewSource(opt.Seed))
	ex := ExamByKey(opt.Exam)
	items = ex.Pool(items)
	var chosen []Pick

	tryAdd := func(it *Item) bool {
		seed := rng.Int63()
		p, err := params(it, seed)
		if err != nil {
			return false
		}
		pick := Pick{Item: it, Seed: seed, Params: p}
		vars := map[string]string{}
		for k, v := range p {
			vars[k] = v
		}
		for _, ns := range it.Namespaces {
			pick.Namespaces = append(pick.Namespaces, Render(ns, vars, nil))
		}
		for _, c := range chosen {
			if conflicts(c, pick) {
				return false
			}
			// Generated sessions cover distinct topics (items you pick
			// yourself may repeat one).
			if len(opt.Only) == 0 && it.Topic != "" && it.Topic == c.Item.Topic {
				return false
			}
		}
		// Every cluster takes 1-2 minutes to start and memory: an exam has at
		// most one besides practice and ops, a generated practice session at
		// most one extra copy of a profile.
		extra, copies := extraClusters(append(pickItems(chosen), it))
		if opt.Mode == "exam" && extra > 1 || opt.Mode != "exam" && len(opt.Only) == 0 && copies > 1 {
			return false
		}
		chosen = append(chosen, pick)
		return true
	}

	if len(opt.Only) > 0 {
		for _, id := range opt.Only {
			it := findItem(items, id)
			if it == nil {
				return nil, fmt.Errorf("unknown item %q (or not part of the %s)", id, ex.Name)
			}
			if !tryAdd(it) {
				return nil, fmt.Errorf("item %q conflicts with another selected item", id)
			}
		}
		return chosen, nil
	}

	var candidates []*Item
	for _, it := range items {
		if !it.Allows(opt.Mode) {
			continue
		}
		if opt.Domain != "" && it.Domain != opt.Domain {
			continue
		}
		if opt.Area != "" && it.Area != opt.Area {
			continue
		}
		candidates = append(candidates, it)
	}
	ordered := prioritize(candidates, stats, rng)

	if opt.Mode == "practice" {
		// "All domains": spread the items like the curriculum (for 10 items
		// 3 troubleshooting, 2-3 architecture, 2 networking, ...).
		if opt.Domain == "" && opt.Count > 1 {
			quota := domainQuotas(ex, opt.Count)
			for _, d := range ex.Domains {
				got := 0
				for _, area := range d.Areas {
					if got >= quota[d.Key] {
						break
					}
					for _, it := range ordered {
						if it.Domain == d.Key && it.Area == area && !inPicks(chosen, it) && tryAdd(it) {
							got++
							break
						}
					}
				}
				for _, it := range ordered {
					if got >= quota[d.Key] {
						break
					}
					if it.Domain == d.Key && !inPicks(chosen, it) && tryAdd(it) {
						got++
					}
				}
			}
		}
		for _, it := range ordered {
			if len(chosen) >= opt.Count {
				break
			}
			if !inPicks(chosen, it) {
				tryAdd(it)
			}
		}
		if opt.Domain == "" {
			// Mixed order instead of grouped by domain.
			rng.Shuffle(len(chosen), func(i, j int) { chosen[i], chosen[j] = chosen[j], chosen[i] })
		}
		if len(chosen) == 0 {
			return nil, fmt.Errorf("no items available")
		}
		return chosen, nil
	}

	// Exam: opt.Count questions, split over the domains by curriculum weight,
	// and their estimated times must fit the duration.
	n := opt.Count
	if n <= 0 {
		n = DefaultExamQuestions
	}
	quota := domainQuotas(ex, n)
	budget := float64(opt.Minutes)
	total := 0.0
	fits := func(it *Item, strict bool) bool {
		if !strict {
			return true
		}
		left := n - len(chosen) - 1 // slots still to fill after this one
		m := examMinutes(it)
		// Keep each pick near the average time still available per slot,
		// so long tasks don't crowd out the remaining questions.
		share := (budget - total) / float64(left+1)
		return m <= 1.6*share && total+m+float64(left)*minExamMinutes <= budget
	}
	add := func(it *Item, strict bool) bool {
		if inPicks(chosen, it) || !fits(it, strict) || !tryAdd(it) {
			return false
		}
		total += examMinutes(it)
		return true
	}
	// Each domain gets its quota: first with items that keep the exam within
	// the time budget, then (if a domain would stay short) without that limit.
	got := map[string]int{}
	// Every domain takes one item per area first,
	// so e.g. cluster and node problems are always part of the exam.
	for _, d := range ex.Domains {
		areas := d.Areas
		for ai, area := range areas {
			if got[d.Key] >= quota[d.Key] {
				break
			}
			later := areas[ai+1 : min(len(areas), ai+1+quota[d.Key]-got[d.Key]-1)]
			done := false
			for _, strict := range []bool{true, false} {
				for _, it := range ordered {
					if it.Domain == d.Key && it.Area == area && !blocksAreas(it, later, d.Key, ordered, chosen) && add(it, strict) {
						got[d.Key]++
						done = true
						break
					}
				}
				if done {
					break
				}
			}
		}
	}
	for _, strict := range []bool{true, false} {
		for _, d := range ex.Domains {
			for _, it := range ordered {
				if got[d.Key] >= quota[d.Key] {
					break
				}
				if it.Domain == d.Key && add(it, strict) {
					got[d.Key]++
				}
			}
		}
	}
	// A domain without enough distinct items: fill up from the others.
	for _, it := range ordered {
		if len(chosen) >= n {
			break
		}
		add(it, false)
	}
	if len(chosen) == 0 {
		return nil, fmt.Errorf("no items available")
	}
	rng.Shuffle(len(chosen), func(i, j int) { chosen[i], chosen[j] = chosen[j], chosen[i] })
	return chosen, nil
}

// DefaultExamQuestions: the real CKA has about 15-20 tasks in 120 minutes.
const DefaultExamQuestions = 17

// The shortest realistic task; used to keep room for the remaining slots.
const minExamMinutes = 3.0

// domainQuotas splits n questions over the domains by weight (largest remainder).
func domainQuotas(ex *Exam, n int) map[string]int {
	quota := map[string]int{}
	type rem struct {
		key  string
		frac float64
	}
	var rems []rem
	used := 0
	for _, d := range ex.Domains {
		exact := float64(n) * float64(d.Weight) / 100
		quota[d.Key] = int(exact)
		used += int(exact)
		rems = append(rems, rem{d.Key, exact - float64(int(exact))})
	}
	sort.SliceStable(rems, func(i, j int) bool { return rems[i].frac > rems[j].frac })
	for i := 0; used < n; i++ {
		quota[rems[i%len(rems)].key]++
		used++
	}
	return quota
}

// examMinutes: the item's time at exam pace (exam_minutes in item.yaml).
func examMinutes(it *Item) float64 {
	if it.ExamMins > 0 {
		return float64(it.ExamMins)
	}
	return float64(it.Minutes)
}

func prioritize(items []*Item, stats map[string]ItemStat, rng *rand.Rand) []*Item {
	out := append([]*Item(nil), items...)
	rng.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	sort.SliceStable(out, func(i, j int) bool {
		a, b := stats[out[i].ID], stats[out[j].ID]
		if a.State() != b.State() {
			return a.State() < b.State()
		}
		if a.State() == StateNew {
			return false
		}
		return a.Last.Before(b.Last)
	})
	return out
}

// blocksAreas: picking it would leave one of the later areas without any
// candidate (e.g. "cluster DNS is down" excludes every item that needs DNS).
func blocksAreas(it *Item, areas []string, domain string, ordered []*Item, chosen []Pick) bool {
	for _, area := range areas {
		ok := false
		for _, cand := range ordered {
			if cand == it || cand.Domain != domain || cand.Area != area || inPicks(chosen, cand) {
				continue
			}
			if !conflicts(Pick{Item: it}, Pick{Item: cand}) {
				ok = true
				break
			}
		}
		if !ok {
			return true
		}
	}
	return false
}

func pickItems(picks []Pick) []*Item {
	items := make([]*Item, len(picks))
	for i, p := range picks {
		items[i] = p.Item
	}
	return items
}

func inPicks(picks []Pick, it *Item) bool {
	for _, p := range picks {
		if p.Item == it {
			return true
		}
	}
	return false
}

func conflicts(a, b Pick) bool {
	for _, x := range a.Namespaces {
		for _, y := range b.Namespaces {
			if x == y && x != "default" {
				return true
			}
		}
	}
	// The tags describe one cluster; an own_cluster item shares it with no one.
	if a.Item.Cluster != b.Item.Cluster || a.Item.OwnCluster || b.Item.OwnCluster {
		return false
	}
	overlap := func(x, y []string) bool {
		for _, a := range x {
			for _, b := range y {
				if a == b {
					return true
				}
			}
		}
		return false
	}
	return overlap(a.Item.Conflicts, b.Item.Conflicts) ||
		overlap(a.Item.Conflicts, b.Item.Needs) || overlap(b.Item.Conflicts, a.Item.Needs)
}

func describePicks(picks []Pick) string {
	var b strings.Builder
	total := 0.0
	keys := ClusterKeys(pickItems(picks))
	for i, p := range picks {
		total += examMinutes(p.Item)
		fmt.Fprintf(&b, "%2d. %-34s %-16s %-8s %3.0f min  w%-2d %v\n", i+1, p.Item.ID, p.Item.Domain, keys[i], examMinutes(p.Item), p.Item.Weight, p.Params)
	}
	fmt.Fprintf(&b, "    %d items, ~%.0f min (exam pace)\n", len(picks), total)
	return b.String()
}
