package main

// tmux integration: while an exam is paused, the app pane is zoomed (the
// shell is hidden) and every other pane of the session ignores input.

import (
	"os"
	"os/exec"
	"strings"
)

func inTmux() bool { return os.Getenv("TMUX") != "" && os.Getenv("TMUX_PANE") != "" }

func tmuxOut(args ...string) string {
	out, err := exec.Command("tmux", args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func otherPanes() []string {
	self := os.Getenv("TMUX_PANE")
	var panes []string
	for _, p := range strings.Fields(tmuxOut("list-panes", "-s", "-t", self, "-F", "#{pane_id}")) {
		if p != self {
			panes = append(panes, p)
		}
	}
	return panes
}

// lockShell hides the shell and blocks typing into it.
func lockShell() {
	if !inTmux() {
		return
	}
	self := os.Getenv("TMUX_PANE")
	for _, p := range otherPanes() {
		exec.Command("tmux", "select-pane", "-d", "-t", p).Run()
	}
	exec.Command("tmux", "select-window", "-t", self).Run()
	exec.Command("tmux", "select-pane", "-t", self).Run()
	if tmuxOut("display", "-p", "-t", self, "#{window_zoomed_flag}") == "0" {
		exec.Command("tmux", "resize-pane", "-Z", "-t", self).Run()
	}
}

// unlockShell undoes lockShell (safe to call when nothing is locked).
func unlockShell() {
	if !inTmux() {
		return
	}
	self := os.Getenv("TMUX_PANE")
	for _, p := range otherPanes() {
		exec.Command("tmux", "select-pane", "-e", "-t", p).Run()
	}
	if tmuxOut("display", "-p", "-t", self, "#{window_zoomed_flag}") == "1" {
		exec.Command("tmux", "resize-pane", "-Z", "-t", self).Run()
	}
}
