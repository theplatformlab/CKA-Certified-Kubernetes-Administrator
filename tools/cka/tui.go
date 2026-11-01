package main

// The interactive app: menu, session setup, the question panel, results,
// history, statistics and cluster management. Runs in the left tmux pane.

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
)

var prog *tea.Program

type screen int

const (
	scrMenu screen = iota
	scrPracticeCfg
	scrPickItems
	scrExamCfg
	scrBusy // preparing / grading / cluster operations: shows a log
	scrSession
	scrOverview
	scrResults
	scrDetail
	scrHistory
	scrStats
	scrClusters
	scrPaused // exam paused: question hidden, shell locked
	scrHelp
)

type (
	logMsg      string
	busyDoneMsg struct {
		err  error
		next screen
	}
	checkDoneMsg struct {
		index   int
		results []CheckResult
	}
	bgCheckDoneMsg struct {
		sess    *Session
		index   int
		results []CheckResult
		started time.Time
		err     error
	}
	tickMsg time.Time
)

var (
	stTitle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	stBar    = lipgloss.NewStyle().Foreground(lipgloss.Color("0")).Background(lipgloss.Color("252"))
	stBarRed = lipgloss.NewStyle().Foreground(lipgloss.Color("231")).Background(lipgloss.Color("160")).Bold(true)
	stDim    = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	stSel    = lipgloss.NewStyle().Foreground(lipgloss.Color("39")).Bold(true)
	stOK     = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
	stBad    = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	stWarn   = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
)

type model struct {
	items  []*Item
	store  *Store
	width  int
	height int
	scr    screen
	cursor int
	flash  string // one-line message in the footer

	// practice config
	domainIdx int // 0 = all
	areaIdx   int // 0 = the whole domain
	countIdx  int
	picked    map[string]bool
	// exam config
	durIdx    int
	questions int

	// busy screen
	busyTitle string
	busyLog   []string
	busyNext  screen
	busyErr   error

	// current session
	sess     *Session
	cur      int
	vp        viewport.Model
	vpContent string // what was last put into vp (for Ctrl+F)
	checking bool
	bgChecking bool      // an exam question is being graded in the background
	bgLast     time.Time // when the last background check finished
	armed    string // key that must be pressed twice ("s" solution, "S" submit, "F" finish)
	saveTick int

	// results / history
	viewSess  *Session
	detailIdx int

	renderCache map[string]string

	// help screen
	helpFrom screen
	// Ctrl+F in the question panel
	finding   bool
	findQuery string
	findLast  string
	findLine  int

	// cached reads of the history (reloaded every few seconds)
	cacheAt      time.Time
	cacheStats   map[string]ItemStat
	cacheList    []*Session
	clusterState map[string]string // name -> running | stopped | ""
}

func (m *model) invalidate() { m.cacheAt = time.Time{} }

func (m *model) load() {
	if time.Since(m.cacheAt) < 3*time.Second {
		return
	}
	m.cacheList = m.store.List()
	m.cacheStats = m.store.Stats()
	m.cacheAt = time.Now()
}

func (m *model) stats() map[string]ItemStat { m.load(); return m.cacheStats }
func (m *model) sessions() []*Session      { m.load(); return m.cacheList }

func (m *model) openSession() *Session {
	for _, s := range m.sessions() {
		if s.Status != StatusFinished {
			return s
		}
	}
	return nil
}

func (m *model) refreshClusters() {
	m.clusterState = clusterStates()
}

var counts = []int{1, 3, 5, 10}
var durations = []int{120, 90, 60}

func newModel(items []*Item, store *Store) *model {
	m := &model{items: items, store: store, picked: map[string]bool{}, renderCache: map[string]string{}, countIdx: 1,
		questions: examQuestionsDefault()}
	m.vp = viewport.New(80, 20)
	return m
}

func (m *model) Init() tea.Cmd { return tick() }

func tick() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg { return tickMsg(t) })
}

// ---- Update ------------------------------------------------------------------

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.vp.Width, m.vp.Height = msg.Width, max(3, msg.Height-3)
		m.renderCache = map[string]string{}
		m.refreshViewport(false)
		return m, nil
	case tickMsg:
		return m, tea.Batch(tick(), m.onTick())
	case logMsg:
		m.busyLog = append(m.busyLog, string(msg))
		return m, nil
	case busyDoneMsg:
		m.busyErr = msg.err
		m.invalidate()
		if msg.next == scrClusters {
			m.refreshClusters()
		}
		if msg.err == nil {
			m.scr, m.cursor = msg.next, 0
			if m.scr == scrSession {
				m.refreshViewport(true)
			}
		}
		return m, nil
	case bgCheckDoneMsg:
		m.bgChecking, m.bgLast = false, time.Now()
		// Results that arrive after submitting (or while paused) are dropped:
		// the final grading decides for itself what to re-check.
		if msg.err == nil && msg.sess == m.sess && m.sess.Status == StatusActive {
			si := m.sess.Items[msg.index]
			si.Checks, si.CheckedAt = msg.results, msg.started
			m.store.Save(m.sess)
		}
		return m, nil
	case checkDoneMsg:
		m.checking = false
		if m.sess != nil && msg.index < len(m.sess.Items) {
			si := m.sess.Items[msg.index]
			si.Checks = msg.results
			m.store.Save(m.sess)
			m.flash = fmt.Sprintf("Check: %d/%d passed", si.Passed(), len(si.Checks))
			m.refreshViewport(false)
		}
		return m, nil
	case tea.KeyMsg:
		return m.onKey(msg)
	}
	var cmd tea.Cmd
	m.vp, cmd = m.vp.Update(msg)
	return m, cmd
}

func (m *model) onTick() tea.Cmd {
	if m.scr != scrSession || m.sess == nil || m.sess.Status != StatusActive {
		return nil
	}
	m.sess.ElapsedSec++
	m.sess.Items[m.cur].TimeSec++
	m.sess.Items[m.cur].SeenAt = time.Now()
	m.saveTick++
	if m.saveTick%15 == 0 {
		m.store.Save(m.sess)
	}
	if m.sess.Mode == "exam" && time.Now().After(m.sess.Deadline) {
		m.flash = "Time is up"
		m.startGrading()
		return nil
	}
	return m.backgroundCheck()
}

// Like killer.sh, exams are graded in the background while they run, one
// question at a time, so submitting only re-checks what was worked on since.
const (
	bgPause   = 20 * time.Second // between two background checks
	bgCurrent = 2 * time.Minute  // the question on screen is re-checked this often
	bgStale   = 5 * time.Minute  // every other question at least this often
	bgMaxAge  = 15 * time.Minute // older results are re-checked when submitting
)

func (m *model) backgroundCheck() tea.Cmd {
	s := m.sess
	if s.Mode != "exam" || m.bgChecking || time.Since(m.bgLast) < bgPause {
		return nil
	}
	idx := nextBackgroundCheck(s, m.cur, time.Now())
	if idx < 0 {
		return nil
	}
	si := s.Items[idx]
	it := findItem(m.items, si.ItemID)
	if it == nil {
		return nil
	}
	m.bgChecking = true
	started := time.Now()
	return func() tea.Msg {
		results, _, err := RunCheck(s, si, it)
		return bgCheckDoneMsg{sess: s, index: idx, results: results, started: started, err: err}
	}
}

// nextBackgroundCheck picks the question to grade next (-1: none is due):
// one that was on screen since its last check, then the question on screen
// now, then the one with the oldest result.
func nextBackgroundCheck(s *Session, cur int, now time.Time) int {
	oldest := func(due func(i int, si *SessionItem) bool) int {
		best := -1
		for i, si := range s.Items {
			if due(i, si) && (best < 0 || si.CheckedAt.Before(s.Items[best].CheckedAt)) {
				best = i
			}
		}
		return best
	}
	if i := oldest(func(i int, si *SessionItem) bool { return i != cur && si.NeedsRecheck() }); i >= 0 {
		return i
	}
	if now.Sub(s.Items[cur].CheckedAt) >= bgCurrent {
		return cur
	}
	return oldest(func(i int, si *SessionItem) bool { return now.Sub(si.CheckedAt) >= bgStale })
}

func (m *model) onKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	key := k.String()
	if key == "ctrl+c" {
		if m.sess != nil && m.sess.Status == StatusActive {
			m.store.Save(m.sess)
		}
		return m, tea.Quit
	}
	m.flash = ""
	armed := m.armed
	m.armed = ""

	if m.finding {
		return m.keyFind(k)
	}
	if key == "?" && m.scr != scrHelp && m.scr != scrBusy && m.scr != scrPaused {
		m.helpFrom, m.scr = m.scr, scrHelp
		m.vp.SetContent(m.markdown("help", keysHelp))
		m.vp.GotoTop()
		return m, nil
	}

	switch m.scr {
	case scrHelp:
		switch key {
		case "esc", "q", "?":
			m.scr = m.helpFrom
			if m.scr == scrSession {
				m.refreshViewport(false)
			} else if m.scr == scrDetail {
				m.refreshDetail()
			}
			return m, nil
		}
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(k)
		return m, cmd
	case scrPaused:
		return m.keyPaused(key)
	case scrMenu:
		return m.keyMenu(key)
	case scrPracticeCfg:
		return m.keyPracticeCfg(key)
	case scrPickItems:
		return m.keyPickItems(key)
	case scrExamCfg:
		return m.keyExamCfg(key)
	case scrBusy:
		if m.busyErr != nil && (key == "enter" || key == "esc" || key == "q") {
			m.busyErr = nil
			m.scr = scrMenu
		}
		return m, nil
	case scrSession:
		return m.keySession(k, armed)
	case scrOverview:
		switch key {
		case "up", "k":
			m.cursor = max(0, m.cursor-1)
		case "down", "j":
			m.cursor = min(len(m.sess.Items)-1, m.cursor+1)
		case "enter":
			m.cur = m.cursor
			m.scr = scrSession
			m.refreshViewport(true)
		case "esc", "o", "q":
			m.scr = scrSession
		}
		return m, nil
	case scrResults:
		switch key {
		case "up", "k":
			m.cursor = max(0, m.cursor-1)
		case "down", "j":
			m.cursor = min(len(m.viewSess.Items)-1, m.cursor+1)
		case "enter":
			m.detailIdx = m.cursor
			m.scr = scrDetail
			m.refreshDetail()
		case "r":
			if m.viewSess.Status != StatusFinished {
				return m.resume(m.viewSess)
			}
		case "esc", "q":
			m.scr, m.cursor = scrMenu, 0
		m.invalidate()
		}
		return m, nil
	case scrDetail:
		switch key {
		case "esc", "q":
			m.scr = scrResults
			return m, nil
		case "n", "right":
			if m.detailIdx < len(m.viewSess.Items)-1 {
				m.detailIdx++
				m.refreshDetail()
			}
			return m, nil
		case "p", "left":
			if m.detailIdx > 0 {
				m.detailIdx--
				m.refreshDetail()
			}
			return m, nil
		}
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(k)
		return m, cmd
	case scrHistory:
		sessions := m.sessions()
		switch key {
		case "up", "k":
			m.cursor = max(0, m.cursor-1)
		case "down", "j":
			m.cursor = min(len(sessions)-1, m.cursor+1)
		case "enter":
			if len(sessions) > 0 {
				m.viewSess = sessions[m.cursor]
				m.scr, m.cursor = scrResults, 0
			}
		case "esc", "q":
			m.scr, m.cursor = scrMenu, 0
		m.invalidate()
		}
		return m, nil
	case scrStats:
		if key == "esc" || key == "q" || key == "enter" {
			m.scr, m.cursor = scrMenu, 0
		m.invalidate()
		}
		return m, nil
	case scrClusters:
		return m.keyClusters(key, armed)
	}
	return m, nil
}

// ---- Menu --------------------------------------------------------------------

type menuEntry struct {
	label  string
	action func() (tea.Model, tea.Cmd)
}

func (m *model) menuEntries() []menuEntry {
	var e []menuEntry
	if open := m.openSession(); open != nil {
		label := fmt.Sprintf("Continue %s session (%d items, started %s)", open.Mode, len(open.Items), open.Created.Format("Jan 2 15:04"))
		if open.Mode == "exam" {
			left := time.Until(open.Deadline)
			if open.RemainingSec > 0 {
				left = time.Duration(open.RemainingSec) * time.Second
				label += fmt.Sprintf(" — paused, %s left", fmtDur(left))
			} else if left > 0 {
				label += fmt.Sprintf(" — running, %s left", fmtDur(left))
			} else {
				label += " — time is up, grade it"
			}
		}
		e = append(e, menuEntry{label, func() (tea.Model, tea.Cmd) { return m.resume(open) }})
	}
	e = append(e,
		menuEntry{"Practice session", func() (tea.Model, tea.Cmd) { m.scr, m.cursor = scrPracticeCfg, 0; return m, nil }},
		menuEntry{"Mock exam", func() (tea.Model, tea.Cmd) { m.scr, m.cursor = scrExamCfg, 0; return m, nil }},
		menuEntry{"History", func() (tea.Model, tea.Cmd) { m.scr, m.cursor = scrHistory, 0; return m, nil }},
		menuEntry{"Statistics", func() (tea.Model, tea.Cmd) { m.scr, m.cursor = scrStats, 0; return m, nil }},
		menuEntry{"Clusters", func() (tea.Model, tea.Cmd) { m.scr, m.cursor = scrClusters, 0; m.refreshClusters(); return m, nil }},
		menuEntry{"Quit", func() (tea.Model, tea.Cmd) { return m, tea.Quit }},
	)
	return e
}

func (m *model) keyMenu(key string) (tea.Model, tea.Cmd) {
	entries := m.menuEntries()
	switch key {
	case "up", "k":
		m.cursor = max(0, m.cursor-1)
	case "down", "j":
		m.cursor = min(len(entries)-1, m.cursor+1)
	case "enter":
		return entries[m.cursor].action()
	case "q":
		return m, tea.Quit
	}
	return m, nil
}

// ---- Practice / exam configuration ------------------------------------------------

func (m *model) keyPracticeCfg(key string) (tea.Model, tea.Cmd) {
	const rows = 5 // domain, area, count, pick, start
	switch key {
	case "up", "k":
		m.cursor = max(0, m.cursor-1)
	case "down", "j":
		m.cursor = min(rows-1, m.cursor+1)
	case "left", "h", "right", "l":
		d := 1
		if key == "left" || key == "h" {
			d = -1
		}
		switch m.cursor {
		case 0:
			m.domainIdx = (m.domainIdx + d + len(Domains) + 1) % (len(Domains) + 1)
			m.areaIdx = 0
		case 1:
			if areas := m.practiceAreas(); len(areas) > 0 {
				m.areaIdx = (m.areaIdx + d + len(areas) + 1) % (len(areas) + 1)
			}
		case 2:
			m.countIdx = (m.countIdx + d + len(counts)) % len(counts)
		}
	case "enter":
		switch m.cursor {
		case 3:
			m.scr, m.cursor = scrPickItems, 0
			m.picked = map[string]bool{}
		case 4:
			opt := GenOptions{Mode: "practice", Count: counts[m.countIdx]}
			if m.domainIdx > 0 {
				opt.Domain = Domains[m.domainIdx-1].Key
			}
			if m.areaIdx > 0 {
				opt.Area = m.practiceAreas()[m.areaIdx-1]
			}
			return m.startSession(opt)
		}
	case "esc", "q":
		m.scr, m.cursor = scrMenu, 0
		m.invalidate()
	}
	return m, nil
}

// practiceAreas: the sub-areas of the selected domain (none for "All domains").
func (m *model) practiceAreas() []string {
	if m.domainIdx == 0 {
		return nil
	}
	return domainAreas[Domains[m.domainIdx-1].Key]
}

func (m *model) areaItemCount(area string) int {
	n := 0
	for _, it := range m.items {
		if it.Allows("practice") && it.Area == area && it.Domain == Domains[m.domainIdx-1].Key {
			n++
		}
	}
	return n
}

// Practice items grouped by domain (curriculum order), then by title.
func (m *model) practiceItems() []*Item {
	var out []*Item
	for _, d := range Domains {
		var group []*Item
		for _, it := range m.items {
			if it.Allows("practice") && it.Domain == d.Key {
				group = append(group, it)
			}
		}
		sort.Slice(group, func(i, j int) bool { return group[i].Label() < group[j].Label() })
		out = append(out, group...)
	}
	return out
}

func (m *model) keyPickItems(key string) (tea.Model, tea.Cmd) {
	items := m.practiceItems()
	switch key {
	case "up", "k":
		m.cursor = max(0, m.cursor-1)
	case "down", "j":
		m.cursor = min(len(items)-1, m.cursor+1)
	case "pgdown":
		m.cursor = min(len(items)-1, m.cursor+10)
	case "pgup":
		m.cursor = max(0, m.cursor-10)
	case " ", "x":
		id := items[m.cursor].ID
		m.picked[id] = !m.picked[id]
	case "enter":
		var only []string
		for _, it := range items {
			if m.picked[it.ID] {
				only = append(only, it.ID)
			}
		}
		if len(only) == 0 {
			only = []string{items[m.cursor].ID}
		}
		return m.startSession(GenOptions{Mode: "practice", Only: only})
	case "esc", "q":
		m.scr, m.cursor = scrPracticeCfg, 2
	}
	return m, nil
}

func (m *model) keyExamCfg(key string) (tea.Model, tea.Cmd) {
	switch key {
	case "up", "k":
		m.cursor = max(0, m.cursor-1)
	case "down", "j":
		m.cursor = min(2, m.cursor+1)
	case "left", "h", "right", "l":
		d := 1
		if key == "left" || key == "h" {
			d = -1
		}
		switch m.cursor {
		case 0:
			m.durIdx = (m.durIdx + d + len(durations)) % len(durations)
		case 1:
			m.questions = min(30, max(5, m.questions+d))
		}
	case "enter":
		if m.cursor == 2 {
			return m.startSession(GenOptions{Mode: "exam", Minutes: durations[m.durIdx], Count: m.questions})
		}
	case "esc", "q":
		m.scr, m.cursor = scrMenu, 0
		m.invalidate()
	}
	return m, nil
}

// ---- Session lifecycle ---------------------------------------------------------

func (m *model) startSession(opt GenOptions) (tea.Model, tea.Cmd) {
	if open := m.openSession(); open != nil {
		// Only one open session at a time: the old one is closed ungraded.
		open.Status = StatusFinished
		open.Finished = time.Now()
		m.store.Save(open)
	}
	opt.Seed = time.Now().UnixNano()
	picks, err := Generate(m.items, m.store.Stats(), opt, EvalParams)
	m.invalidate()
	if err != nil {
		m.flash = "Could not build a session: " + err.Error()
		return m, nil
	}
	s := &Session{
		ID:          time.Now().Format("20060102-150405"),
		Mode:        opt.Mode,
		Status:      StatusActive,
		Created:     time.Now(),
		DurationMin: opt.Minutes,
		Clusters:    clustersFor(opt.Mode),
	}
	if opt.Mode == "exam" {
		s.Network = "kind-exam"
	}
	keys := ClusterKeys(pickItems(picks))
	for i, p := range picks {
		if keys[i] != p.Item.Cluster {
			// An own_cluster item next to others: a copy of its profile's
			// cluster ("ops2": cka-exam-ops -> cka-exam-ops2).
			s.Clusters[keys[i]] = s.Clusters[p.Item.Cluster] + strings.TrimPrefix(keys[i], p.Item.Cluster)
		}
		s.Items = append(s.Items, &SessionItem{
			ItemID: p.Item.ID, Title: p.Item.Title, Domain: p.Item.Domain,
			Seed: p.Seed, Params: p.Params, Weight: p.Item.Weight, Minutes: p.Item.Minutes,
			Workdir: filepath.Join(homeDir(), "cka-lab", fmt.Sprintf("q%02d", i+1)),
		})
		if opt.Mode == "exam" {
			s.Items[i].Namespace = examNamespace(p.Item)
		}
		if keys[i] != p.Item.Cluster {
			s.Items[i].Cluster = keys[i]
		}
	}
	m.store.Save(s)
	m.sess, m.cur = s, 0
	fresh := opt.Mode == "exam"
	title := fmt.Sprintf("Preparing %s session: %d items", opt.Mode, len(s.Items))
	return m, m.runBusy(title, scrSession, func(log func(string)) error {
		if err := Prepare(s, m.items, fresh, log); err != nil {
			// A half-prepared session can't be continued: drop it.
			m.store.Delete(s)
			m.sess = nil
			return fmt.Errorf("%v — the session was discarded, start it again", err)
		}
		if s.Mode == "exam" {
			s.Deadline = time.Now().Add(time.Duration(s.DurationMin) * time.Minute)
			if os.Getenv("CKA_NO_BROWSER") != "" {
				log("Docs browser disabled (CKA_NO_BROWSER)")
			} else if err := browser("start"); err != nil {
				log("Docs browser not started: " + err.Error())
			}
		}
		switchContext(s.Clusters["practice"])
		m.store.Save(s)
		return nil
	})
}

func switchContext(cluster string) {
	if cluster != "" && clusterExists(cluster) {
		runQuiet("kubectl", "config", "use-context", "kind-"+cluster)
	}
}

func (m *model) resume(s *Session) (tea.Model, tea.Cmd) {
	unlockShell()
	m.sess, m.cur = s, 0
	if s.Mode == "exam" && s.RemainingSec == 0 && time.Now().After(s.Deadline) {
		m.startGrading()
		return m, nil
	}
	return m, m.runBusy("Resuming "+s.Mode+" session", scrSession, func(log func(string)) error {
		// Paused sessions may have stopped clusters (exam pause stops them).
		var stopped []string
		for _, k := range sessionClusters(s, m.items) {
			name := s.Clusters[k]
			if !clusterExists(name) {
				return fmt.Errorf("cluster %s no longer exists — the session can't be resumed", name)
			}
			if !clusterRunning(name) {
				stopped = append(stopped, name)
			}
		}
		if err := startClusters(stopped, log); err != nil {
			return err
		}
		if s.Mode == "exam" && s.RemainingSec > 0 {
			s.Deadline = time.Now().Add(time.Duration(s.RemainingSec) * time.Second)
			s.RemainingSec = 0
			if os.Getenv("CKA_NO_BROWSER") == "" {
				if err := browser("start"); err != nil {
					log("Docs browser not started: " + err.Error())
				}
			}
		}
		switchContext(s.Clusters["practice"])
		s.Status = StatusActive
		m.store.Save(s)
		return nil
	})
}

// pauseExam freezes the timer and stops the exam clusters to free memory.
// softPause freezes the exam timer, hides the question and locks the shell.
// The clusters keep running (x on the pause screen stops them too).
func (m *model) softPause() {
	s := m.sess
	s.RemainingSec = max(1, int(time.Until(s.Deadline).Seconds()))
	s.Status = StatusPaused
	m.store.Save(s)
	lockShell()
	m.scr = scrPaused
}

func (m *model) unpause() {
	s := m.sess
	s.Deadline = time.Now().Add(time.Duration(s.RemainingSec) * time.Second)
	s.RemainingSec = 0
	s.Status = StatusActive
	m.store.Save(s)
	unlockShell()
	m.scr = scrSession
	m.refreshViewport(false)
}

func (m *model) keyPaused(key string) (tea.Model, tea.Cmd) {
	switch key {
	case "u", "U", "enter":
		m.unpause()
	case "x", "X":
		unlockShell()
		return m, m.stopExamClusters()
	case "m", "M":
		unlockShell()
		m.scr, m.cursor = scrMenu, 0
		m.invalidate()
	}
	return m, nil
}

// stopExamClusters shuts the paused exam's clusters down to free memory;
// "Continue" in the menu starts them again.
func (m *model) stopExamClusters() tea.Cmd {
	s := m.sess
	return m.runBusy("Shutting down the exam clusters", scrMenu, func(log func(string)) error {
		browser("stop")
		for _, k := range sessionClusters(s, m.items) {
			log("Stopping cluster " + s.Clusters[k] + " ...")
			if err := stopCluster(s.Clusters[k]); err != nil {
				return err
			}
		}
		log(fmt.Sprintf("Exam paused with %s left. Continue from the menu.", fmtDur(time.Duration(s.RemainingSec)*time.Second)))
		return nil
	})
}

// runBusy runs fn in the background and shows its log; on success the app
// moves to next.
func (m *model) runBusy(title string, next screen, fn func(log func(string)) error) tea.Cmd {
	m.scr, m.busyTitle, m.busyLog, m.busyErr, m.busyNext = scrBusy, title, nil, nil, next
	return func() tea.Msg {
		log := func(s string) { prog.Send(logMsg(s)) }
		err := fn(log)
		return busyDoneMsg{err: err, next: next}
	}
}

func (m *model) startGrading() {
	s := m.sess
	if s == nil || m.scr == scrBusy {
		return
	}
	s.Status = StatusPaused // not "active": the timer must stop while grading
	m.viewSess = s
	cmd := m.runBusy("Grading ...", scrResults, func(log func(string)) error {
		var stopped []string
		for _, k := range sessionClusters(s, m.items) {
			if name := s.Clusters[k]; clusterExists(name) && !clusterRunning(name) {
				stopped = append(stopped, name)
			}
		}
		if err := startClusters(stopped, log); err != nil {
			return err
		}
		for i, si := range s.Items {
			it := findItem(m.items, si.ItemID)
			if it == nil {
				continue
			}
			if s.Mode == "exam" && !si.NeedsRecheck() && time.Since(si.CheckedAt) < bgMaxAge {
				log(fmt.Sprintf("Checked %d/%d: %s (graded during the exam)", i+1, len(s.Items), si.Title))
			} else {
				log(fmt.Sprintf("Checking %d/%d: %s", i+1, len(s.Items), si.Title))
				si.CheckedAt = time.Now()
				si.Checks, _, _ = RunCheck(s, si, it)
			}
			si.Graded, si.GradedAt = true, time.Now()
			si.ApplyBaseline()
		}
		s.Status, s.Finished = StatusFinished, time.Now()
		m.store.Save(s)
		if s.Mode == "exam" {
			browser("stop")
		} else {
			log("Cleaning up ...")
			Cleanup(s, m.items, log)
		}
		return nil
	})
	go func() { prog.Send(cmd()) }()
}

// ---- Session panel -------------------------------------------------------------

func (m *model) keySession(k tea.KeyMsg, armed string) (tea.Model, tea.Cmd) {
	key := k.String()
	s := m.sess
	si := s.Items[m.cur]
	practice := s.Mode == "practice"
	switch key {
	case "n", "right":
		if m.cur < len(s.Items)-1 {
			m.cur++
			m.refreshViewport(true)
		}
	case "p", "left":
		if m.cur > 0 {
			m.cur--
			m.refreshViewport(true)
		}
	case "f":
		si.Flagged = !si.Flagged
		m.store.Save(s)
	case "o":
		m.scr, m.cursor = scrOverview, m.cur
	case "h":
		if !practice {
			m.flash = "No hints in an exam"
			break
		}
		it := findItem(m.items, si.ItemID)
		doc, _ := it.Doc()
		if si.HintsShown < len(doc.Hints) {
			si.HintsShown++
			m.store.Save(s)
			m.refreshViewport(false)
			m.vp.GotoBottom()
		} else if len(doc.Hints) == 0 {
			m.flash = "This item has no hints"
		} else {
			m.flash = "All hints are shown"
		}
	case "c":
		if !practice {
			m.flash = "Checking is only possible in practice sessions"
			break
		}
		if m.checking {
			break
		}
		m.checking = true
		m.flash = "Checking ..."
		idx := m.cur
		it := findItem(m.items, si.ItemID)
		return m, func() tea.Msg {
			results, _, _ := RunCheck(s, si, it)
			return checkDoneMsg{index: idx, results: results}
		}
	case "s":
		if !practice {
			break
		}
		if si.SolutionViewed {
			break
		}
		if armed != "s" {
			m.armed, m.flash = "s", "Press s again to reveal the solution"
			break
		}
		si.SolutionViewed = true
		m.store.Save(s)
		m.refreshViewport(false)
	case "ctrl+f":
		m.finding, m.findQuery = true, ""
	case "P":
		if !practice {
			m.softPause()
			break
		}
		s.Status = StatusPaused
		m.store.Save(s)
		m.scr, m.cursor = scrMenu, 0
		m.invalidate()
	case "S", "F":
		if armed != key {
			m.armed = key
			if practice {
				m.flash = "Press F again to finish: grade all items and clean up"
			} else {
				m.flash = "Press S again to submit the exam"
			}
			break
		}
		m.startGrading()
	case "q", "esc":
		if practice {
			s.Status = StatusPaused
		}
		m.store.Save(s)
		m.scr, m.cursor = scrMenu, 0
		m.invalidate()
	default:
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(k)
		return m, cmd
	}
	return m, nil
}

func (m *model) markdown(key, md string) string {
	if out, ok := m.renderCache[key]; ok {
		return out
	}
	width := max(30, m.width-2)
	r, err := glamour.NewTermRenderer(glamour.WithStandardStyle("dark"), glamour.WithWordWrap(width))
	if err != nil {
		return md
	}
	out, err := r.Render(md)
	if err != nil {
		return md
	}
	m.renderCache[key] = out
	return out
}

func (m *model) refreshViewport(top bool) {
	if m.sess == nil || m.scr != scrSession && m.scr != scrBusy {
		return
	}
	s := m.sess
	si := s.Items[m.cur]
	it := findItem(m.items, si.ItemID)
	if it == nil {
		m.vp.SetContent("Item " + si.ItemID + " no longer exists in the pool.")
		return
	}
	doc, err := it.Doc()
	if err != nil {
		m.vp.SetContent(err.Error())
		return
	}
	vars, clusters := itemVars(s, si, it), s.ItemClusters(si, it)
	var b strings.Builder
	question := doc.Question
	if s.Mode == "exam" && s.Status != StatusFinished {
		question = ExamView(question, m.cur+1)
	}
	b.WriteString(Render(question, vars, clusters))
	if si.SetupError != "" {
		b.WriteString("\n\n> ⚠ The setup of this item failed: " + si.SetupError + "\n")
	}
	if s.Mode == "practice" {
		for i := 0; i < si.HintsShown && i < len(doc.Hints); i++ {
			fmt.Fprintf(&b, "\n\n**Hint %d:** %s", i+1, Render(doc.Hints[i], vars, clusters))
		}
		if si.SolutionViewed {
			b.WriteString("\n\n---\n\n## Solution\n\n" + Render(doc.Solution, vars, clusters))
			if doc.Notes != "" {
				b.WriteString("\n\n" + Render(doc.Notes, vars, clusters))
			}
		}
	}
	key := fmt.Sprintf("%s/%d/%d/%v", si.ItemID, m.cur, si.HintsShown, si.SolutionViewed)
	content := m.markdown(key, b.String())
	if s.Mode == "practice" && len(si.Checks) > 0 {
		content += "\n" + renderChecks(si.Checks)
	}
	m.vp.SetContent(content)
	m.vpContent = content
	if top {
		m.vp.GotoTop()
	}
}

func renderChecks(checks []CheckResult) string {
	var b strings.Builder
	passed := 0
	for _, c := range checks {
		if c.Pass {
			passed++
		}
	}
	b.WriteString(stTitle.Render(fmt.Sprintf("  Last check: %d/%d", passed, len(checks))) + "\n")
	for _, c := range checks {
		if c.Pass {
			b.WriteString("  " + stOK.Render("✓") + " " + c.Desc + "\n")
		} else {
			b.WriteString("  " + stBad.Render("✗") + " " + c.Desc + "\n")
			if c.Detail != "" {
				b.WriteString("      " + stWarn.Render(c.Detail) + "\n")
			}
		}
	}
	return b.String()
}

// keyFind: typing a search term for Ctrl+F (Enter searches, Esc cancels;
// Ctrl+F + Enter on an empty term jumps to the next match of the last one).
func (m *model) keyFind(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch k.Type {
	case tea.KeyEsc:
		m.finding = false
	case tea.KeyEnter:
		m.finding = false
		q := m.findQuery
		if q == "" {
			q = m.findLast
		} else {
			m.findLine = -1
		}
		if q == "" {
			return m, nil
		}
		m.findLast = q
		all := strings.Split(stripANSI(m.currentContent()), "\n")
		for i := 1; i <= len(all); i++ {
			n := (m.findLine + i) % len(all)
			if strings.Contains(strings.ToLower(all[n]), strings.ToLower(q)) {
				m.findLine = n
				m.vp.SetYOffset(max(0, n-2))
				m.flash = fmt.Sprintf("found %q (Ctrl+F, Enter: next)", q)
				return m, nil
			}
		}
		m.flash = fmt.Sprintf("%q not found", q)
	case tea.KeyBackspace:
		if r := []rune(m.findQuery); len(r) > 0 {
			m.findQuery = string(r[:len(r)-1])
		}
	case tea.KeySpace:
		m.findQuery += " "
	case tea.KeyRunes:
		m.findQuery += string(k.Runes)
	}
	return m, nil
}

// currentContent: the text in the question viewport.
func (m *model) currentContent() string { return m.vpContent }

// ---- Results ---------------------------------------------------------------------

func (m *model) refreshDetail() {
	s := m.viewSess
	si := s.Items[m.detailIdx]
	var b strings.Builder
	fmt.Fprintf(&b, "%s\n%s · weight %d · %d/%d checks\n\n", stTitle.Render(si.Title), domainName(si.Domain), si.Weight, si.Passed(), len(si.Checks))
	if len(si.Checks) > 0 {
		b.WriteString(renderChecks(si.Checks))
	} else {
		b.WriteString(stDim.Render("  not graded") + "\n")
	}
	if it := findItem(m.items, si.ItemID); it != nil {
		if doc, err := it.Doc(); err == nil {
			vars, clusters := itemVars(s, si, it), s.ItemClusters(si, it)
			md := Render(doc.Question, vars, clusters) + "\n\n# Solution\n\n" + Render(doc.Solution, vars, clusters)
			if doc.Notes != "" {
				md += "\n\n" + Render(doc.Notes, vars, clusters)
			}
			b.WriteString(m.markdown(fmt.Sprintf("detail/%s/%s", s.ID, si.ItemID), md))
		}
	}
	m.vp.SetContent(b.String())
	m.vp.GotoTop()
}

// ---- Clusters ----------------------------------------------------------------------

type clusterRow struct{ profile, name, network string }

func clusterRows() []clusterRow {
	return []clusterRow{
		{"practice", "cka-practice", ""}, {"ops", "cka-ops", ""}, {"ops", "cka-ops2", ""}, {"cni", "cka-cni", ""}, {"runtime", "cka-runtime", ""}, {"ha", "cka-ha", ""},
		{"practice", "cka-exam", "kind-exam"}, {"ops", "cka-exam-ops", "kind-exam"}, {"ops", "cka-exam-ops2", "kind-exam"}, {"cni", "cka-exam-cni", "kind-exam"},
		{"runtime", "cka-exam-runtime", "kind-exam"}, {"ha", "cka-exam-ha", "kind-exam"},
	}
}

func (m *model) keyClusters(key, armed string) (tea.Model, tea.Cmd) {
	rows := clusterRows()
	switch key {
	case "up", "k":
		m.cursor = max(0, m.cursor-1)
	case "down", "j":
		m.cursor = min(len(rows)-1, m.cursor+1)
	case "c", "r":
		row := rows[m.cursor]
		recreate := key == "r"
		if key == "c" && clusterExists(row.name) {
			m.flash = row.name + " already exists (r recreates it)"
			return m, nil
		}
		if recreate && armed != "r" {
			m.armed, m.flash = "r", "Press r again to recreate "+row.name
			return m, nil
		}
		return m, m.runBusy("Creating "+row.name, scrClusters, func(log func(string)) error {
			log("init-cluster.sh --profile " + row.profile + " (1-2 minutes) ...")
			f, _ := os.CreateTemp("", "cka-cluster-*.log")
			defer f.Close()
			if err := createCluster(row.profile, row.name, row.network, recreate, f); err != nil {
				return fmt.Errorf("failed, see %s", f.Name())
			}
			log("Done")
			return nil
		})
	case "s":
		row := rows[m.cursor]
		if m.clusterState[row.name] != "running" {
			return m, nil
		}
		return m, m.runBusy("Stopping "+row.name, scrClusters, func(log func(string)) error {
			return stopCluster(row.name)
		})
	case "u":
		row := rows[m.cursor]
		if m.clusterState[row.name] != "stopped" {
			return m, nil
		}
		return m, m.runBusy("Starting "+row.name, scrClusters, func(log func(string)) error {
			return startCluster(row.name, log)
		})
	case "d":
		row := rows[m.cursor]
		if armed != "d" {
			m.armed, m.flash = "d", "Press d again to delete "+row.name
			return m, nil
		}
		return m, m.runBusy("Deleting "+row.name, scrClusters, func(log func(string)) error {
			return deleteCluster(row.name, discard{})
		})
	case "esc", "q":
		m.scr, m.cursor = scrMenu, 0
		m.invalidate()
	}
	return m, nil
}

type discard struct{}

func (discard) Write(p []byte) (int, error) { return len(p), nil }

// ---- View --------------------------------------------------------------------------

func (m *model) View() string {
	if m.width == 0 {
		return ""
	}
	var body string
	var footer string
	switch m.scr {
	case scrMenu:
		body, footer = m.viewMenu(), "↑/↓ select · enter open · ? keys · q quit"
	case scrPracticeCfg:
		body, footer = m.viewPracticeCfg(), "↑/↓ row · ←/→ change · enter start · esc back"
	case scrPickItems:
		body, footer = m.viewPickItems(), "space select · enter start (selection or current) · esc back"
	case scrExamCfg:
		body, footer = m.viewExamCfg(), "↑/↓ row · ←/→ change · enter start · esc back"
	case scrBusy:
		body = m.viewBusy()
		if m.busyErr != nil {
			footer = "enter back to menu"
		}
	case scrSession:
		return m.viewSession()
	case scrPaused:
		return m.viewPaused()
	case scrHelp:
		return m.vp.View() + "\n" + stDim.Render("↑/↓ scroll · esc back")
	case scrOverview:
		body, footer = m.viewOverview(), "enter jump · esc back"
	case scrResults:
		body, footer = m.viewResults(), "enter details · esc menu"
		if m.viewSess.Status != StatusFinished {
			footer = "r resume · enter details · esc menu"
		}
	case scrDetail:
		return m.vp.View() + "\n" + stDim.Render("↑/↓ scroll · n/p next/prev item · esc back")
	case scrHistory:
		body, footer = m.viewHistory(), "enter open · esc back"
	case scrStats:
		body, footer = m.viewStats(), "esc back"
	case scrClusters:
		body, footer = m.viewClusters(), "c create · u start · s stop · r recreate · d delete · esc back"
	}
	if m.flash != "" {
		footer = stWarn.Render(m.flash)
	}
	lines := strings.Split(body, "\n")
	if len(lines) > m.height-2 {
		lines = lines[:m.height-2]
	}
	pad := m.height - 1 - len(lines)
	return strings.Join(lines, "\n") + strings.Repeat("\n", max(1, pad)) + stDim.Render(footer)
}

func (m *model) viewMenu() string {
	var b strings.Builder
	b.WriteString(stTitle.Render("CKA Lab") + "\n")
	stats := m.stats()
	nNew, nFail, nPass := 0, 0, 0
	for _, it := range m.items {
		switch stats[it.ID].State() {
		case StateNew:
			nNew++
		case StateFailed:
			nFail++
		default:
			nPass++
		}
	}
	b.WriteString(stDim.Render(fmt.Sprintf("%d items · %d new · %d failed last time · %d passed", len(m.items), nNew, nFail, nPass)) + "\n\n")
	for i, e := range m.menuEntries() {
		if i == m.cursor {
			b.WriteString(stSel.Render("› "+e.label) + "\n")
		} else {
			b.WriteString("  " + e.label + "\n")
		}
	}
	return b.String()
}

// info renders a dim explanatory text wrapped to the pane width (the
// hard-coded line breaks are only paragraph hints).
func (m *model) info(text string) string {
	text = strings.ReplaceAll(text, "\n", " ")
	return stDim.Width(max(20, m.width-2)).Render(text)
}

func cursorLine(sel bool, s string) string {
	if sel {
		return stSel.Render("› " + s)
	}
	return "  " + s
}

func (m *model) viewPracticeCfg() string {
	domain := "All domains"
	if m.domainIdx > 0 {
		domain = Domains[m.domainIdx-1].Name
	}
	var b strings.Builder
	b.WriteString(stTitle.Render("Practice session") + "\n")
	b.WriteString(m.info("Soft time targets, hints (h), checks (c) and solutions (s) on demand, pause anytime (P).") + "\n\n")
	area := "All areas"
	if m.domainIdx == 0 {
		area = "–"
	} else if m.areaIdx > 0 {
		a := m.practiceAreas()[m.areaIdx-1]
		area = fmt.Sprintf("%s (%d items)", areaName(a), m.areaItemCount(a))
	}
	b.WriteString(cursorLine(m.cursor == 0, "Domain:  ‹ "+domain+" ›") + "\n")
	b.WriteString(cursorLine(m.cursor == 1, "Area:    ‹ "+area+" ›") + "\n")
	b.WriteString(cursorLine(m.cursor == 2, fmt.Sprintf("Items:   ‹ %d ›", counts[m.countIdx])) + "\n")
	b.WriteString(cursorLine(m.cursor == 3, "Choose items myself …") + "\n")
	b.WriteString(cursorLine(m.cursor == 4, "Start") + "\n\n")
	b.WriteString(m.info("With “All domains”, the items are spread over the domains like the curriculum. Pick a domain to choose one of its areas, e.g. Helm & Kustomize. Items you haven't done come first, then items you failed last time, one per topic.\nSessions use cka-practice (and cka-ops / cka-cni / cka-runtime when an item needs them)."))
	return b.String()
}

func stateMark(s ItemStat) string {
	switch s.State() {
	case StateNew:
		return stDim.Render("·")
	case StateFailed:
		return stBad.Render("✗")
	}
	return stOK.Render("✓")
}

func (m *model) viewPickItems() string {
	items := m.practiceItems()
	stats := m.stats()
	var b strings.Builder
	b.WriteString(stTitle.Render("Choose items") + stDim.Render("   · new  ✗ failed last time  ✓ passed") + "\n\n")
	visible := max(5, m.height-5)
	start := 0
	if m.cursor >= visible {
		start = m.cursor - visible + 1
	}
	for i := start; i < len(items) && i < start+visible; i++ {
		it := items[i]
		box := "[ ]"
		if m.picked[it.ID] {
			box = "[x]"
		}
		line := fmt.Sprintf("%s %s %-44s %-15s %2dm", box, stateMark(stats[it.ID]), truncate(it.Label(), 44), it.Domain, it.Minutes)
		if it.Cluster != "practice" {
			line += " " + stDim.Render(it.Cluster)
		}
		b.WriteString(cursorLine(i == m.cursor, line) + "\n")
	}
	return b.String()
}

func (m *model) viewExamCfg() string {
	var b strings.Builder
	b.WriteString(stTitle.Render("Mock exam") + "\n")
	b.WriteString(m.info("Questions are drawn from the pool, weighted like the CKA curriculum, one per topic.\nHard timer, no hints, graded when you submit (S S) or the time runs out.") + "\n\n")
	b.WriteString(cursorLine(m.cursor == 0, fmt.Sprintf("Duration:  ‹ %d min ›", durations[m.durIdx])) + "\n")
	b.WriteString(cursorLine(m.cursor == 1, fmt.Sprintf("Questions: ‹ %d ›", m.questions)) + "\n")
	b.WriteString(cursorLine(m.cursor == 2, "Start") + "\n\n")
	b.WriteString(m.info("Starting builds fresh clusters cka-exam and cka-exam-ops (2-3 minutes)\nand opens the docs-only browser. The timer starts when everything is ready."))
	for _, d := range Domains {
		b.WriteString("\n" + stDim.Render(fmt.Sprintf("  %-24s %d%%", d.Name, d.Weight)))
	}
	return b.String()
}

func (m *model) viewBusy() string {
	var b strings.Builder
	b.WriteString(stTitle.Render(m.busyTitle) + "\n\n")
	lines := m.busyLog
	if len(lines) > m.height-6 {
		lines = lines[len(lines)-(m.height-6):]
	}
	for _, l := range lines {
		b.WriteString(truncate(l, m.width-2) + "\n")
	}
	if m.busyErr != nil {
		b.WriteString("\n" + stBad.Render("Error: "+m.busyErr.Error()) + "\n")
	} else {
		b.WriteString(stDim.Render("…") + "\n")
	}
	return b.String()
}

func (m *model) viewSession() string {
	s := m.sess
	si := s.Items[m.cur]
	left := fmt.Sprintf(" Q%d/%d · %s · w%d", m.cur+1, len(s.Items), domainName(si.Domain), si.Weight)
	if s.Mode == "exam" {
		// Like the real exam: question number and weight, no topic.
		left = fmt.Sprintf(" Question %d of %d · weight %d%%", m.cur+1, len(s.Items), weightPercent(s, si))
	}
	if si.Flagged {
		left += " · ⚑"
	}
	var right string
	bar := stBar
	if s.Mode == "exam" {
		rem := time.Until(s.Deadline)
		if rem < 0 {
			rem = 0
		}
		right = "⏱ " + fmtDur(rem) + " left "
		if rem < 10*time.Minute {
			bar = stBarRed
		}
	} else {
		right = fmt.Sprintf("this item %s / ~%dm · total %s ", fmtDur(time.Duration(si.TimeSec)*time.Second), si.Minutes, fmtDur(time.Duration(s.ElapsedSec)*time.Second))
		if si.TimeSec > si.Minutes*60 {
			right = "⚠ " + right
		}
	}
	gap := max(1, m.width-lipgloss.Width(left)-lipgloss.Width(right))
	header := bar.Render(left + strings.Repeat(" ", gap) + right)

	keys := "n/p · ↑/↓ · ^F find · f flag · o overview · P pause · S S submit · ? keys"
	if s.Mode == "practice" {
		keys = "n/p · ↑/↓ · h hint · c check · s s solution · o overview · P pause · F F finish · ? keys"
	}
	footer := stDim.Render(keys)
	if m.flash != "" {
		footer = stWarn.Render(m.flash)
	}
	if m.finding {
		footer = stSel.Render("find: " + m.findQuery + "▏") + stDim.Render("  (enter search · esc cancel)")
	}
	return header + "\n" + m.vp.View() + "\n" + footer
}

func (m *model) viewOverview() string {
	var b strings.Builder
	b.WriteString(stTitle.Render("Overview") + "\n\n")
	for i, si := range m.sess.Items {
		mark := " "
		if si.Flagged {
			mark = "⚑"
		}
		status := ""
		if len(si.Checks) > 0 && m.sess.Mode == "practice" {
			status = fmt.Sprintf(" %d/%d", si.Passed(), len(si.Checks))
		}
		line := fmt.Sprintf("%s %2d. %-44s %-15s w%-2d%s", mark, i+1, truncate(si.Title, 44), si.Domain, si.Weight, status)
		if m.sess.Mode == "exam" {
			line = fmt.Sprintf("%s Question %2d   %2d%%", mark, i+1, weightPercent(m.sess, si))
		}
		b.WriteString(cursorLine(i == m.cursor, line) + "\n")
	}
	return b.String()
}

func (m *model) viewResults() string {
	s := m.viewSess
	var b strings.Builder
	score := s.Score()
	verdict := ""
	if s.Mode == "exam" {
		if score >= 66 {
			verdict = stOK.Render("  PASS (66% needed)")
		} else {
			verdict = stBad.Render("  FAIL (66% needed)")
		}
	}
	b.WriteString(stTitle.Render(fmt.Sprintf("%s session %s", capitalize(s.Mode), s.Created.Format("Jan 2 2006 15:04"))) + "\n")
	b.WriteString(fmt.Sprintf("Score %.0f%%%s · %s\n\n", score, verdict, s.Status))
	for i, si := range s.Items {
		mark := stDim.Render("·")
		switch {
		case !si.Graded:
		case si.FullyPassed():
			mark = stOK.Render("✓")
		default:
			mark = stBad.Render("✗")
		}
		extra := ""
		if si.SolutionViewed {
			extra += stDim.Render(" (solution viewed)")
		}
		line := fmt.Sprintf("%s %-44s %-15s %2d/%-2d %s%s", mark, truncate(si.Title, 44), si.Domain, si.Passed(), len(si.Checks), scoreBar(si.Score()), extra)
		b.WriteString(cursorLine(i == m.cursor, line) + "\n")
	}
	if s.Mode == "exam" && s.Status == StatusFinished {
		b.WriteString("\n" + m.info("The exam clusters stay up for inspection (Clusters menu to delete them)."))
	}
	return b.String()
}

func scoreBar(f float64) string {
	n := int(f*10 + 0.5)
	return stOK.Render(strings.Repeat("█", n)) + stDim.Render(strings.Repeat("░", 10-n))
}

func (m *model) viewHistory() string {
	sessions := m.sessions()
	var b strings.Builder
	b.WriteString(stTitle.Render("History") + "\n")
	b.WriteString(stDim.Render("Stored in "+m.storePath()+" (one JSON file per session)") + "\n\n")
	if len(sessions) == 0 {
		b.WriteString(stDim.Render("No sessions yet."))
	}
	visible := max(5, m.height-5)
	start := 0
	if m.cursor >= visible {
		start = m.cursor - visible + 1
	}
	for i := start; i < len(sessions) && i < start+visible; i++ {
		s := sessions[i]
		score := fmt.Sprintf("%3.0f%%", s.Score())
		if s.Status != StatusFinished {
			score = "  — "
		}
		line := fmt.Sprintf("%s  %-8s %-8s %2d items  %s", s.Created.Format("2006-01-02 15:04"), s.Mode, s.Status, len(s.Items), score)
		b.WriteString(cursorLine(i == m.cursor, line) + "\n")
	}
	return b.String()
}

func (m *model) viewStats() string {
	stats := m.stats()
	var b strings.Builder
	b.WriteString(stTitle.Render("Statistics") + "\n")
	b.WriteString(stDim.Render("Computed from the sessions in "+m.storePath()) + "\n\n")
	b.WriteString(fmt.Sprintf("  %-30s %6s %6s %6s %6s %8s\n", "Domain", "items", "new", "failed", "passed", "attempts"))
	for _, d := range Domains {
		var total, nNew, nFail, nPass, attempts int
		for _, it := range m.items {
			if it.Domain != d.Key {
				continue
			}
			total++
			st := stats[it.ID]
			attempts += st.Attempts
			switch st.State() {
			case StateNew:
				nNew++
			case StateFailed:
				nFail++
			default:
				nPass++
			}
		}
		b.WriteString(fmt.Sprintf("  %-30s %6d %6d %6d %6d %8d\n", d.Name+fmt.Sprintf(" (%d%%)", d.Weight), total, nNew, nFail, nPass, attempts))
	}
	var exams []*Session
	for _, s := range m.sessions() {
		if s.Mode == "exam" && s.Status == StatusFinished {
			exams = append(exams, s)
		}
	}
	if len(exams) > 0 {
		b.WriteString("\n  Last mock exams: ")
		for i, s := range exams {
			if i == 5 {
				break
			}
			b.WriteString(fmt.Sprintf("%.0f%%  ", s.Score()))
		}
		b.WriteString("\n")
	}
	return b.String()
}

func (m *model) viewClusters() string {
	var b strings.Builder
	b.WriteString(stTitle.Render("Clusters") + "\n\n")
	for i, r := range clusterRows() {
		state := stDim.Render("not created")
		switch m.clusterState[r.name] {
		case "running":
			state = stOK.Render("running")
		case "stopped":
			state = stWarn.Render("stopped")
		}
		b.WriteString(cursorLine(i == m.cursor, fmt.Sprintf("%-18s %-9s %s", r.name, r.profile, state)) + "\n")
	}
	b.WriteString("\n" + m.info("Stopped clusters keep their state and use no memory. Sessions start or create\nthe clusters they need; exams always recreate cka-exam*. Pausing an exam stops them."))
	return b.String()
}

func fmtDur(d time.Duration) string {
	d = d.Round(time.Second)
	h, mnt, sec := int(d.Hours()), int(d.Minutes())%60, int(d.Seconds())%60
	if h > 0 {
		return fmt.Sprintf("%d:%02d:%02d", h, mnt, sec)
	}
	return fmt.Sprintf("%d:%02d", mnt, sec)
}

func truncate(s string, n int) string {
	r := []rune(s)
	if n <= 1 || len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func runQuiet(name string, args ...string) {
	exec.Command(name, args...).Run()
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// weightPercent: the item's share of the exam's total weight.
func weightPercent(s *Session, si *SessionItem) int {
	total := 0
	for _, it := range s.Items {
		total += it.Weight
	}
	if total == 0 {
		return 0
	}
	return (si.Weight*100 + total/2) / total
}

func (m *model) viewPaused() string {
	s := m.sess
	left := fmtDur(time.Duration(s.RemainingSec) * time.Second)
	box := lipgloss.NewStyle().Border(lipgloss.DoubleBorder()).Padding(1, 4).BorderForeground(lipgloss.Color("214"))
	body := stTitle.Render("EXAM PAUSED") + "\n\n" +
		fmt.Sprintf("Time left: %s (frozen)\n", left) +
		"The question and the shell are hidden until you resume.\n\n" +
		stSel.Render("u") + "  resume the exam\n" +
		stSel.Render("x") + "  also shut down the exam clusters (frees memory; Continue from the menu starts them again)\n" +
		stSel.Render("m") + "  back to the menu, clusters keep running, timer stays paused"
	out := box.Width(min(m.width-4, 90)).Render(body)
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, out)
}

// storePath: the session directory, with the home directory shown as ~.
func (m *model) storePath() string {
	if h := homeDir(); h != "" && strings.HasPrefix(m.store.Dir, h) {
		return "~" + strings.TrimPrefix(m.store.Dir, h) + "/"
	}
	return m.store.Dir + "/"
}
