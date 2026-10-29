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
	Mode    string // exam | practice
	Minutes int    // exam duration
	Domain  string // practice: "" = all
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

// Items on these clusters need a cluster of their own; an exam includes at
// most one of them so the start-up doesn't take forever.
var specialClusters = map[string]bool{"cni": true, "runtime": true, "ha": true}

func Generate(items []*Item, stats map[string]ItemStat, opt GenOptions, params ParamFunc) ([]Pick, error) {
	rng := rand.New(rand.NewSource(opt.Seed))
	var chosen []Pick

	tryAdd := func(it *Item) bool {
		seed := rng.Int63()
		p, err := params(it, seed)
		if err != nil {
			return false
		}
		pick := Pick{Item: it, Seed: seed, Params: p}
		for _, ns := range it.Namespaces {
			pick.Namespaces = append(pick.Namespaces, Render(ns, p, nil))
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
			if opt.Mode == "exam" && specialClusters[it.Cluster] && specialClusters[c.Item.Cluster] {
				return false
			}
		}
		chosen = append(chosen, pick)
		return true
	}

	if len(opt.Only) > 0 {
		for _, id := range opt.Only {
			it := findItem(items, id)
			if it == nil {
				return nil, fmt.Errorf("unknown item %q", id)
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
		candidates = append(candidates, it)
	}
	ordered := prioritize(candidates, stats, rng)

	if opt.Mode == "practice" {
		for _, it := range ordered {
			if len(chosen) >= opt.Count {
				break
			}
			tryAdd(it)
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
	quota := domainQuotas(n)
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
		return m <= 1.4*share && total+m+float64(left)*minExamMinutes <= budget
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
	for _, strict := range []bool{true, false} {
		for _, d := range Domains {
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
const minExamMinutes = 5.0

// domainQuotas splits n questions over the domains by weight (largest remainder).
func domainQuotas(n int) map[string]int {
	quota := map[string]int{}
	type rem struct {
		key  string
		frac float64
	}
	var rems []rem
	used := 0
	for _, d := range Domains {
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

// Exercise times are learning times; in an exam they take roughly 60% of that.
func examMinutes(it *Item) float64 {
	if it.Exercise {
		return float64(max(6, it.Minutes*6/10))
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
	for i, p := range picks {
		total += examMinutes(p.Item)
		fmt.Fprintf(&b, "%2d. %-34s %-16s %-8s %3.0f min  w%-2d %v\n", i+1, p.Item.ID, p.Item.Domain, p.Item.Cluster, examMinutes(p.Item), p.Item.Weight, p.Params)
	}
	fmt.Fprintf(&b, "    %d items, ~%.0f min (exam pace)\n", len(picks), total)
	return b.String()
}
