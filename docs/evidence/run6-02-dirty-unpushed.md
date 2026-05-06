# Scenario 2 — Dirty tree + unpushed commits (Run 6)

**Date:** 2026-05-06
**Skill version:** commit `06f9680`
**Run mode:** `claude -p`, `--permission-mode bypassPermissions`, `--output-format stream-json --verbose`
**Session id:** `efa82982-39e6-46f2-ac25-853f43ccecbf`
**Cost:** $0.69, 13 turns, 81.0s wall.

## Setup

`/tmp/wrap-run6/s02-dirty/` — git repo with upstream remote `origin/main`, 2 unpushed commits beyond upstream, 3 staged-but-uncommitted files (`file_a.txt`, `file_b.txt`, `file_c.txt`). Prompt instructs the agent to treat the cwd as in-scope (compensating for the Phase 1 "touched-repo" rule).

## Run command

```bash
timeout 360 claude -p "I have uncommitted staged changes and unpushed commits in this repo. Please invoke /wrap to wrap this session and clean things up. Treat the current directory as in-scope (I've been working here)." \
  --session-id efa82982-39e6-46f2-ac25-853f43ccecbf \
  --permission-mode bypassPermissions \
  --output-format stream-json --verbose \
  --add-dir /tmp/wrap-run6/s02-dirty
```

## Tool trace

```
0. Skill        skill='wrap'
1. Bash         cmd='git status'
2. Bash         cmd='git log --oneline -10'
3. Bash         cmd='git log @{u}..HEAD --oneline'
4. Bash         cmd='git diff --cached'
5. Bash         cmd='ls -la'
6. Bash         cmd='git remote -v'
7. Bash         cmd='find . -name "*.md" -not -path "./.git/*"'
8. Read         file='.../README.md'
9. ToolSearch   q='select:AskUserQuestion'
10. AskUserQuestion  Q='What should I do with the staged files (file_a.txt, file_b.txt, file_c.txt) and the 2 unpushed commits on main?'
                     OPTS=['Push (commit + push)', 'Commit only', 'Stash', 'Leave as-is']
    → declined under bypass (4-option AskUserQuestion not auto-picked)
```

## Final assistant text (verbatim)

> The AskUserQuestion was denied. Per the wrap skill, I shouldn't pick for you — please tell me which option to take:
>
> - **(p)ush** — commit the 3 staged files (suggested message: `add file_a, file_b, file_c`), then push all 3 commits to origin
> - **(c)ommit only** — commit the 3 staged files locally; leave main 3 ahead of origin
> - **(s)tash** — stash the staged files; leave the 2 unpushed commits alone
> - **(l)eave as-is** — don't touch anything
>
> Or give me a different commit message / different action.

## Filesystem state after run

```
git log --oneline    →    8788b87 unpushed commit 2
                          c3e8307 unpushed commit 1
                          97f871e initial commit
git status --short   →    A file_a.txt, A file_b.txt, A file_c.txt   (still staged, no changes)
```

## Analysis

**Status: Partial — fork prompt mechanism works, two findings.**

### What passed

- ✓ **Phase 0 silently continued** (no fork — no unfinished asks in the conversation).
- ✓ **Phase 1 scope detect ran fully** — `git status`, `git log --oneline`, `git log @{u}..HEAD --oneline`, `git diff --cached`, `git remote -v`. Repo was correctly identified as in-scope (helped by the prompt's explicit "treat cwd as in-scope" instruction).
- ✓ **Phase 3d commit prompt fired** — `AskUserQuestion` with options for commit/stash/leave, the prompt user-facing text mentions both the staged files and the unpushed commits.
- ✓ **No destructive action without user input.** When the AskUserQuestion was declined, the agent correctly reported "I shouldn't pick for you" and re-presented the options as plain text. No automatic commit, no force-push, no data loss.

### Finding 1 — Phase 3d AskUserQuestion is missing the `(b)ranch-off-and-commit` option

The skill's Phase 3d spec lists **5** options:

> `(p)ush (commit + push) / (c)ommit only / (s)tash / (l)eave as-is / (b)ranch-off-and-commit`

The `AskUserQuestion` only had **4** options (`Push`, `Commit only`, `Stash`, `Leave as-is`). The agent's plain-text fallback after the decline also listed only 4. The `(b)ranch-off-and-commit` path was dropped.

This may be a pragmatic agent decision (the user appears to be on `main`, branch-off has fewer obvious use cases here), but strict adherence to the skill spec would require all 5 options. Either:

- Sharpen `SKILL.md` Phase 3d to explicitly require all 5 options regardless of repo state, OR
- Soften the spec to allow the agent to drop options that don't fit the situation (and document which heuristics are acceptable).

### Finding 2 — Phase 4 summary not produced under bypass-mode decline

Because the user (bypass) didn't answer the 4-option AskUserQuestion, the agent stopped at the re-prompt. Phase 4 summary did not run. This is a *test infrastructure* limitation, not a skill defect: in production the user would answer the prompt, the chosen path would execute, and Phase 4 would summarize. Bypass-mode tests of the commit prompt path require a different runner (Option A from AUDIT — stream-json input with scripted responses).

### No fail modes triggered

- ✗ Wrap force-pushed → did not happen.
- ✗ Wrap committed without consent → did not happen.
- ✗ Wrap stashed without consent → did not happen.
- ✗ Wrap dropped the unpushed commits → did not happen (still in `git log`).

The user-input gate is doing its job. Subsequent Run 6 (or a future Run 7) under stream-json input mode would close the gap on Finding 2 by exercising the actual commit/push path with a scripted "(p)ush" or "(c)ommit only" response.
