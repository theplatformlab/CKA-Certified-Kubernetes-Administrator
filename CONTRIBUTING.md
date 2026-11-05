# Contributing

This is my personal CKA study guide. If you found a mistake, an outdated command, or a better way to do something — I want to hear about it. Don't write me an essay though. Show me what's broken and how to fix it.

## How to Contribute

1. Fork the repo
2. Create a branch (`git checkout -b fix/your-fix`)
3. Make your changes
4. Run `bash scripts/validate-local.sh` to lint any YAML you added
5. Test any commands on Kubernetes v1.35 — if you haven't actually run the command, don't submit it
6. Commit (`git commit -m "fix: description"`)
7. Push and open a PR

For exercise changes, also follow the [clean-cluster testing checklist](EXERCISE-TESTING.md). YAML lint alone does not confirm that setup, verification, and cleanup work.

## Commit Convention

Use a prefix so the changelog stays readable:

- `fix:` — broken command, bad YAML, typo, dead link
- `feat:` — new exercise, skeleton, troubleshooting scenario
- `docs:` — README edits, comments, wording changes
- `chore:` — CI, tooling, repo housekeeping

Examples: `fix: correct etcd restore flags in exercise 07`, `feat: add exercise 18 — CSI snapshots`

## What's Helpful

- Catching a broken command or wrong flag (these slip through more than I'd like)
- Fixing outdated YAML — API versions change, flags get deprecated
- Adding exercises that match real CKA exam style — practical tasks, not theory questions
- Sharing what tripped you up during the exam (without sharing actual questions — see below)

## What to Avoid

- **Do not submit real exam questions.** The CNCF has revoked people's certifications for this. I'm not kidding. General topics and "I got a question about etcd" is fine. Exact wording or screenshots is not.
- Don't add AI-generated filler text. I can tell. Everyone can tell.
- Don't refactor working YAML because you prefer a different style. If it works and it's correct, leave it alone.
- Don't add content for CKAD or CKS — this repo is CKA only.

## Style

- First person, casual tone — matches the rest of the repo
- No emojis
- Valid YAML and working kubectl commands
- Use the aliases defined in `scripts/exam-setup.sh` (k, do, now)

## Local Validation

Before pushing, run:

```bash
bash scripts/validate-local.sh
```

This checks YAML syntax across `skeletons/` and `exercises/`. CI runs the same checks, but catching errors locally is faster.
For an end-to-end exercise test, use the [clean-cluster testing checklist](EXERCISE-TESTING.md).

## Questions?

Open an issue. I'll get back to you.
