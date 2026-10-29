package main

// Session generation: picks items from the pool.
//   exam:     curriculum-weighted by domain, within a time budget
//   practice: a number of items, optionally from one domain
// Within a domain, never-attempted items come first, then items whose last
// attempt failed, then passed ones (least recently practised first).

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
	Count   int    // practice: number of items
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

	// Exam: fill each domain's share of the time budget.
	budget := float64(opt.Minutes) * 0.95
	used := map[string]float64{}
	total := 0.0
	for _, d := range Domains {
		target := budget * float64(d.Weight) / 100
		for _, it := range ordered {
			if it.Domain != d.Key || used[d.Key] >= target*0.8 {
				continue
			}
			m := examMinutes(it)
			if used[d.Key] > 0 && used[d.Key]+m > target*1.2 {
				continue
			}
			if inPicks(chosen, it) {
				continue
			}
			if tryAdd(it) {
				used[d.Key] += m
				total += m
			}
		}
	}
	// Top up with whatever fits if some domain ran short.
	for _, it := range ordered {
		if total >= budget*0.9 {
			break
		}
		if inPicks(chosen, it) || total+examMinutes(it) > budget {
			continue
		}
		if tryAdd(it) {
			total += examMinutes(it)
		}
	}
	if len(chosen) == 0 {
		return nil, fmt.Errorf("no items available")
	}
	rng.Shuffle(len(chosen), func(i, j int) { chosen[i], chosen[j] = chosen[j], chosen[i] })
	return chosen, nil
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
