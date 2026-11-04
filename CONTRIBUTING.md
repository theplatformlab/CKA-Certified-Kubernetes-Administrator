# Contributing

This repo is a hands-on lab for the CKA, CKAD and CKS plus study guides for all three. If you found a mistake, an outdated command, or a better way to do something, open an issue or a PR. Keep it short: show what's broken and how to fix it.

## How to Contribute

1. Create a branch (`git checkout -b fix/your-fix`)
2. Make your changes
3. For a lab item: run its setup, check, solution and cleanup for real (see [docs/lab.md](docs/lab.md#writing-an-item)), then `cd tools/cka && go test ./...`
4. Test any commands on Kubernetes v1.35 — if you haven't actually run the command, don't submit it
5. Commit (`git commit -m "fix: description"`)
6. Push and open a PR against `main`

## Commit Convention

Use a prefix so the changelog stays readable:

- `fix:` — broken command, bad YAML, typo, dead link
- `feat:` — new lab item, template, troubleshooting scenario
- `docs:` — README edits, comments, wording changes
- `chore:` — CI, tooling, repo housekeeping

Examples: `fix: correct etcd restore flags in etcd-backup-restore`, `feat: add a CSI snapshot item`

## What's Helpful

- Catching a broken command or wrong flag (these slip through)
- Fixing outdated YAML — API versions change, flags get deprecated
- Adding lab items that match real exam style — practical tasks, not theory questions
- Sharing what tripped you up during the exam (without sharing actual questions — see below)

## What to Avoid

- **Do not submit real exam questions.** The CNCF has revoked people's certifications for this. General topics and "I got a question about etcd" is fine. Exact wording or screenshots is not.
- Don't add filler text. Every sentence should help someone pass or fix something.
- Don't refactor working YAML because you prefer a different style. If it works and it's correct, leave it alone.
- Don't duplicate a skill the pool already trains. The lab serves CKA, CKAD and CKS from one pool; give an item the right `area` instead of copying it for another exam.

## Style

- Direct, practical tone — advice, not anecdotes
- No emojis
- Valid YAML and working kubectl commands
- Use the aliases defined in `scripts/exam-setup.sh` (k, do, now)

## Local Validation

Before pushing, run:

```bash
cd tools/cka && go test ./...
```

The pool test loads every item and checks its metadata, README parts, areas and namespaces. CI runs it too, plus a syntax check of every `lab.sh` and script.

## Questions?

Open an issue.
