# Contributing

This repo is a hands-on lab for the CKA, CKAD and CKS plus a CKA study guide. If you found a mistake, an outdated command, or a better way to do something, open an issue or a PR. Keep it short: show what's broken and how to fix it.

## How to Contribute

1. Fork the repo
2. Create a branch (`git checkout -b fix/your-fix`)
3. Make your changes
4. For a lab item: run its setup, check, solution and cleanup for real (see [LAB.md](LAB.md#writing-an-item)), then `cd tools/cka && go test ./...`
5. Test any commands on Kubernetes v1.35 — if you haven't actually run the command, don't submit it
6. Commit (`git commit -m "fix: description"`)
7. Push and open a PR

## Commit Convention

Use a prefix so the changelog stays readable:

- `fix:` — broken command, bad YAML, typo, dead link
- `feat:` — new lab item, template, troubleshooting scenario
- `docs:` — README edits, comments, wording changes
- `chore:` — CI, tooling, repo housekeeping

Examples: `fix: correct etcd restore flags in etcd-backup-restore`, `feat: add a CSI snapshot item`

## What's Helpful

- Catching a broken command or wrong flag (these slip through more than I'd like)
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

The pool test loads every item and checks its metadata, README parts, areas and namespaces. CI runs it too, plus a syntax check of every `lab.sh`.

## Questions?

Open an issue.
