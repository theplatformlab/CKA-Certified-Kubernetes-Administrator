// cka — practice sessions and mock exams from the item pool of this repo.
//
//	cka                 interactive app (normally started through ./cka, which
//	                    puts it into a tmux layout next to a shell)
//	cka list            list the pool
//	cka gen exam [min] [questions]  preview a generated exam (nothing is created)
//	cka gen practice [domain] [count]
//	                    (CKA_EXAM=ckad|cks: for another certification)
//	cka render <id>     print an item's task as the app shows it
//	cka keys            the key reference (exam environment, lab, app)
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	repoRoot = findRepoRoot()
	items, err := LoadBank(repoRoot)
	if err != nil {
		fail(err)
	}
	store, err := NewStore()
	if err != nil {
		fail(err)
	}

	args := os.Args[1:]
	if len(args) == 0 || args[0] == "ui" {
		prog = tea.NewProgram(newModel(items, store), tea.WithAltScreen())
		_, err := prog.Run()
		unlockShell() // never leave the shell locked behind (exam pause screen)
		if err != nil {
			fail(err)
		}
		return
	}
	switch args[0] {
	case "list":
		stats := store.Stats()
		for _, it := range items {
			st := stats[it.ID]
			state := map[int]string{StateNew: "new", StateFailed: "failed", StatePassed: "passed"}[st.State()]
			var exams []string
			for _, ex := range Exams {
				if d, _ := ex.place(it); d != "" {
					exams = append(exams, ex.Name)
				}
			}
			fmt.Printf("%-32s %-20s %-8s %3dm w%-2d %-17v %-7s %-14s %s\n", it.ID, it.Area, it.Cluster, it.Minutes, it.Weight, it.Modes, state, strings.Join(exams, ","), it.Title)
		}
	case "gen":
		opt := GenOptions{Mode: "exam", Minutes: 120, Count: 3, Seed: time.Now().UnixNano()}
		if len(args) > 1 {
			opt.Mode = args[1]
		}
		if opt.Mode == "exam" {
			opt.Count = examQuestionsDefault()
			if len(args) > 2 {
				opt.Minutes, _ = strconv.Atoi(args[2])
			}
			if len(args) > 3 {
				opt.Count, _ = strconv.Atoi(args[3])
			}
		}
		if opt.Mode == "practice" {
			if len(args) > 2 && args[2] != "all" {
				opt.Domain = args[2]
			}
			if len(args) > 3 {
				opt.Count, _ = strconv.Atoi(args[3])
			}
		}
		opt.Exam = os.Getenv("CKA_EXAM") // cka (default) | ckad | cks
		if s := os.Getenv("CKA_GEN_SEED"); s != "" {
			opt.Seed, _ = strconv.ParseInt(s, 10, 64)
		}
		picks, err := Generate(items, store.Stats(), opt, EvalParams)
		if err != nil {
			fail(err)
		}
		fmt.Print(describePicks(picks))
	case "keys":
		fmt.Print(keysHelp)
	case "render":
		if len(args) < 2 {
			fail(fmt.Errorf("usage: cka render <item-id>"))
		}
		it := findItem(items, args[1])
		if it == nil {
			fail(fmt.Errorf("unknown item %s", args[1]))
		}
		doc, err := it.Doc()
		if err != nil {
			fail(err)
		}
		params, _ := EvalParams(it, 1)
		s := &Session{Clusters: clustersFor("practice")}
		si := &SessionItem{Params: params, Workdir: homeDir() + "/cka-lab/q01"}
		vars := itemVars(s, si, it)
		fmt.Println(Render(doc.Question, vars, s.Clusters))
		fmt.Printf("\n--- %d hints ---\n", len(doc.Hints))
		for _, h := range doc.Hints {
			fmt.Println("- " + Render(h, vars, s.Clusters))
		}
		fmt.Printf("\n--- solution: %d chars, notes: %d chars ---\n", len(doc.Solution), len(doc.Notes))
	default:
		fail(fmt.Errorf("unknown command %q (ui, list, gen, render, keys)", args[0]))
	}
}

// examQuestionsDefault: CKA_EXAM_QUESTIONS or the built-in default (17).
func examQuestionsDefault() int {
	if v, err := strconv.Atoi(os.Getenv("CKA_EXAM_QUESTIONS")); err == nil && v > 0 {
		return v
	}
	return DefaultExamQuestions
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "cka:", err)
	os.Exit(1)
}
