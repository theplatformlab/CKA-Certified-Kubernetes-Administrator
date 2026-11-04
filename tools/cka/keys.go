package main

// The key reference: shown with "?" in the app, by `cka keys`, and by the
// `exam-help` command in the lab shell.

const keysHelp = `# Keys

## Exam environment (as on the real CKA)

These work like in the PSI exam desktop
(docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad):

| Key | Action |
|---|---|
| Ctrl+Shift+C / Ctrl+Shift+V | copy / paste in the terminal |
| Selecting text with the mouse | copies it (also question text in the left pane) |
| Ctrl+Alt+W | delete the word before the cursor (Ctrl+W does nothing, like on the exam, where it would close the browser tab) |
| Insert | disabled, like on the exam: use i in vim |
| Ctrl+F | find text in the question |
| ssh <node> | open a shell on a node; exit to return |

On the exam the terminal also has k (kubectl) with completion; so does the lab shell.
In the docs browser (Firefox) Ctrl+F finds in the page; on the exam, use Ctrl+Alt+W
instead of Ctrl+W there too.

## Lab layout (tmux)

| Key | Action |
|---|---|
| click a pane, or Ctrl+b ← / → | switch between questions and shell |
| Ctrl+b c / Ctrl+b n | new shell window / next window |
| exam-help | print this reference in the shell |

## Question panel

| Key | Action |
|---|---|
| n / p (→ / ←) | next / previous question |
| ↑ ↓ PgUp PgDn | scroll |
| Ctrl+F | find in the question (Enter again: next match) |
| f | flag the question |
| o | overview of all questions |
| ? | this help |
| h | next hint (practice) |
| c | check this item now (practice) |
| s s | show the solution (practice) |
| P | pause: practice → back to the menu; exam → pause screen |
| F F / S S | finish the practice session / submit the exam |
| q | back to the menu (an exam's timer keeps running) |

## Exam pause screen

| Key | Action |
|---|---|
| u | resume: timer and shell continue |
| x | shut the exam clusters down too (frees memory; "Continue" starts them again) |
| m | back to the menu, clusters keep running, timer stays paused |
`
