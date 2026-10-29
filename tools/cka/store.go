package main

// Session history in ~/.local/share/cka-lab/sessions/<id>.json.
// Item statistics (new / failed / passed) are derived from all sessions.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type CheckResult struct {
	Pass   bool   `json:"pass"`
	Desc   string `json:"desc"`
	Detail string `json:"detail,omitempty"`
}

type SessionItem struct {
	ItemID         string            `json:"item"`
	Title          string            `json:"title"`
	Domain         string            `json:"domain"`
	Seed           int64             `json:"seed"`
	Params         map[string]string `json:"params,omitempty"`
	Workdir        string            `json:"workdir"`
	Weight         int               `json:"weight"`
	Minutes        int               `json:"minutes"`
	SetupError     string            `json:"setupError,omitempty"`
	HintsShown     int               `json:"hintsShown"`
	SolutionViewed bool              `json:"solutionViewed"`
	Flagged        bool              `json:"flagged"`
	TimeSec        int               `json:"timeSec"`
	Checks         []CheckResult     `json:"checks,omitempty"`
	Graded         bool              `json:"graded"`
	GradedAt       time.Time         `json:"gradedAt,omitempty"`
}

func (si *SessionItem) Passed() int {
	n := 0
	for _, c := range si.Checks {
		if c.Pass {
			n++
		}
	}
	return n
}

// Score in [0,1]: share of passed checks.
func (si *SessionItem) Score() float64 {
	if len(si.Checks) == 0 {
		return 0
	}
	return float64(si.Passed()) / float64(len(si.Checks))
}

func (si *SessionItem) FullyPassed() bool {
	return si.Graded && len(si.Checks) > 0 && si.Passed() == len(si.Checks)
}

const (
	StatusActive   = "active"
	StatusPaused   = "paused"
	StatusFinished = "finished"
)

type Session struct {
	ID          string            `json:"id"`
	Mode        string            `json:"mode"` // exam | practice
	Status      string            `json:"status"`
	Created     time.Time         `json:"created"`
	Finished    time.Time         `json:"finished,omitempty"`
	DurationMin int               `json:"durationMin,omitempty"`
	Deadline    time.Time         `json:"deadline,omitempty"`
	ElapsedSec  int               `json:"elapsedSec"`
	Clusters    map[string]string `json:"clusters"`
	Network     string            `json:"network,omitempty"`
	Items       []*SessionItem    `json:"items"`
}

// Score in percent, weighted by item weight.
func (s *Session) Score() float64 {
	var got, max float64
	for _, it := range s.Items {
		got += float64(it.Weight) * it.Score()
		max += float64(it.Weight)
	}
	if max == 0 {
		return 0
	}
	return 100 * got / max
}

type Store struct{ Dir string }

func NewStore() (*Store, error) {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		base = filepath.Join(home, ".local", "share")
	}
	dir := filepath.Join(base, "cka-lab", "sessions")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Store{Dir: dir}, nil
}

func (st *Store) Save(s *Session) error {
	raw, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	tmp := filepath.Join(st.Dir, s.ID+".json.tmp")
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(st.Dir, s.ID+".json"))
}

// All sessions, newest first.
func (st *Store) List() []*Session {
	files, _ := filepath.Glob(filepath.Join(st.Dir, "*.json"))
	var out []*Session
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var s Session
		if json.Unmarshal(raw, &s) == nil {
			out = append(out, &s)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Created.After(out[j].Created) })
	return out
}

// The newest session that is not finished, if any.
func (st *Store) Open() *Session {
	for _, s := range st.List() {
		if s.Status != StatusFinished {
			return s
		}
	}
	return nil
}

// ---- Item statistics ---------------------------------------------------------

const (
	StateNew = iota
	StateFailed
	StatePassed
)

type ItemStat struct {
	Attempts int
	Passes   int
	Last     time.Time
	LastPass bool
}

func (s ItemStat) State() int {
	switch {
	case s.Attempts == 0:
		return StateNew
	case !s.LastPass:
		return StateFailed
	default:
		return StatePassed
	}
}

func (st *Store) Stats() map[string]ItemStat {
	stats := map[string]ItemStat{}
	sessions := st.List()
	// oldest first, so "Last" ends up being the newest attempt
	for i := len(sessions) - 1; i >= 0; i-- {
		for _, it := range sessions[i].Items {
			if !it.Graded {
				continue
			}
			s := stats[it.ItemID]
			s.Attempts++
			if it.FullyPassed() {
				s.Passes++
			}
			if it.GradedAt.After(s.Last) || s.Last.IsZero() {
				s.Last = it.GradedAt
				s.LastPass = it.FullyPassed()
			}
			stats[it.ItemID] = s
		}
	}
	return stats
}
