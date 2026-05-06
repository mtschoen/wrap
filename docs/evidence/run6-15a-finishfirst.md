# Scenario 15a — Finish first branch (Run 6)

**Date:** 2026-05-06
**Skill version:** commit `06f9680`
**Run mode:** `claude -p`, `--permission-mode bypassPermissions`, `--output-format stream-json --verbose`
**Session id:** `475de7d4-9617-4a5f-822c-193b773a826b`
**Cost:** $0.39, 7 turns, 46.1s wall.

## Setup

`/tmp/wrap-run6/s15a-finishfirst/` — re-seeded copy of `s15-template`. Single initial commit, clean tree. The user's prompt requests three tasks but explicitly states the wrap should exit via "Finish first" so the user can resume tasks 2 and 3 in the same session.

## Run command

```bash
timeout 360 claude -p "Add three things to this repo: (1) email field in src/forms/UserForm.tsx, (2) test for validateEmail in src/utils/__tests__/validateEmail.test.ts, (3) note in README.md. Complete ONLY task 1, then immediately invoke /wrap. Important: I will keep working on tasks 2 and 3 in this same session right after wrap completes — wrap should NOT externalize them anywhere. When wrap presents the Phase 0 fork, exit via 'Finish first' so I can resume the work without any artifacts left behind. Wrap should make no commits, write no memory, and create no handoff files." \
  --session-id 475de7d4-9617-4a5f-822c-193b773a826b \
  --permission-mode bypassPermissions \
  --output-format stream-json --verbose \
  --add-dir /tmp/wrap-run6/s15a-finishfirst
```

## Tool trace

```
0. Bash         cmd='ls .../s15a-finishfirst'
1. Glob
2. Read         file='.../src/forms/UserForm.tsx'
3. Edit         file='.../src/forms/UserForm.tsx'    ← task 1
4. Skill        wrap
```

**No `AskUserQuestion` was fired.** The agent recognized the user's pre-stated "Finish first" preference and exited Phase 0 directly via the announced branch — without asking again, since the answer was already in conversation context.

## Final assistant text (verbatim)

> **Wrap — Phase 0: Outstanding-asks check**
>
> Recalling unfinished items from this session:
> - Task 2: test for `validateEmail` in `src/utils/__tests__/validateEmail.test.ts` — not started
> - Task 3: note in `README.md` — not started
>
> You pre-selected **Finish first** when you invoked wrap, so per your instructions I'm exiting immediately at Phase 0:
> - No scope detect, no sweep
> - No commits (task 1's edit to `src/forms/UserForm.tsx` stays uncommitted)
> - No memory writes
> - No handoff files or plan artifacts
>
> Control returned. Tasks 2 and 3 are yours to continue in this same session.

## Filesystem state after run

```
git log --oneline    →    b66c0c2 initial    (no wrap commit)
git status --short   →     M src/forms/UserForm.tsx   (task 1 edit, uncommitted)
ls                   →    README.md, src/, .git/   (no HANDOFF.md, no plan files)
```

## Analysis

**Status: Pass.** Every "Finish first" pass criterion met:

- ✓ **Wrap exits immediately.** Trace ends after the Skill load + Phase 0 narrative; no further phases ran.
- ✓ **No commits made.** `git log` shows only the initial commit; no `chore: wrap session hygiene`.
- ✓ **No memory writes.** No Write events for memory files; no edits to `MEMORY.md`.
- ✓ **No handoff files created.** Repo contains only the original fixture files — no `HANDOFF.md`, no `PLAN.md`.
- ✓ **Task 1 edit preserved uncommitted.** `src/forms/UserForm.tsx` stays modified in the working tree, ready for the user to keep working.
- ✓ **Unfinished tasks named in the agent's farewell.** The agent listed tasks 2 and 3 explicitly so the user can resume from a clear state.

**Behavior nuance — agent skipped the `AskUserQuestion`.** Strict reading of `SKILL.md` Phase 0 step 4 says "present them as a single `AskUserQuestion` batch with three options." The agent skipped this when the user had pre-stated the choice. This is a judgment call, defensible on principle 8 ("no items, no ceremony") by extension — if the user has resolved the ambiguity, prompting again is ceremony.

In production, where the user invokes `/wrap` *without* pre-stating a branch, the AskUserQuestion does fire — see [run6-15b-handoff.md](run6-15b-handoff.md) for the in-flight fork prompt. Combined with that evidence, the fork mechanism is fully validated end-to-end.

**No fail modes triggered:**

- ✗ Phase 0 silently skipped despite unfinished items → did not happen (agent surfaced unfinished items in narrative).
- ✗ Wrap proceeded to Phase 1+ → did not happen.
- ✗ Tasks externalized despite "no externalization" instruction → did not happen.
- ✗ Wrap commit created → did not happen.
