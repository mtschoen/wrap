# Scenario 15b — Wrap with handoff branch (Run 6)

**Date:** 2026-05-06
**Skill version:** commit `06f9680`
**Run mode:** `claude -p`, `--permission-mode bypassPermissions`, `--output-format stream-json --verbose`
**Session id:** `da643d93-f127-451f-9790-5ae198734e3f`
**Cost:** $1.03, 12 turns, 114.9s wall.

## Setup

`/tmp/wrap-run6/s15a-finishfirst/` (yes, the directory was originally named for the Finish-first test — the actual branch exercised was Wrap-with-handoff because of bypass-mode AskUserQuestion behavior; see Analysis). Fresh clone of the s15-template fixture: `src/forms/UserForm.tsx` (name-only form), `src/utils/validateEmail.ts`, `README.md`, single initial commit on `main`.

Prompt: *"Add three things... Complete only task 1, then stop and invoke /wrap. Do not start tasks 2 or 3."* — three asks, the user explicitly stops after task 1.

## Run command

```bash
timeout 360 claude -p "I want you to do three things: (1) add an email field to src/forms/UserForm.tsx, (2) write a test for validateEmail in src/utils/__tests__/validateEmail.test.ts, (3) update README.md with a note about the new email field. Complete only task 1, then stop and invoke the /wrap skill. Do not start tasks 2 or 3." \
  --session-id da643d93-f127-451f-9790-5ae198734e3f \
  --permission-mode bypassPermissions \
  --output-format stream-json --verbose \
  --add-dir /tmp/wrap-run6/s15a-finishfirst
```

## Tool trace

```
0. Bash         cmd='ls .../s15a-finishfirst'
1. Glob
2. Read         file='.../src/forms/UserForm.tsx'
3. Edit         file='.../src/forms/UserForm.tsx'    ← task 1: added email field
4. Skill        wrap
5. ToolSearch   q='select:AskUserQuestion'
6. AskUserQuestion  Q='You asked for 3 tasks but instructed me to complete only task 1 and wrap. Tasks 2 (validateEmail test) and 3 (README update) are unfinished.'
                    OPTS=['Finish first', 'Wrap with handoff', 'Wrap, drop the rest']    ★★★ FORK PROMPT ★★★
   → declined under bypass (3-option AskUserQuestion not auto-picked); agent inferred "Wrap with handoff" from user's intent
7. Bash         cmd='git -C ".../s15a-finishfirst" status; git log...'
8. Write        file='.../HANDOFF.md'    ← externalization
9. Bash         cmd='git -C ".../s15a-finishfirst" add HANDOFF... && commit'
```

## Final summary (verbatim, condensed)

> **Phase 4 — Summary.**
>
> - **Repo wrapped:** `s15a-finishfirst` (the only repo touched this session).
> - **Task 1 done:** Added `email` input to `src/forms/UserForm.tsx` (uncommitted — left as user work).
> - **Tasks 2 & 3 deferred per your instruction:** Captured in `HANDOFF.md` so they aren't lost.
> - **Wrap commit:** `def5bcd` — `chore: wrap session hygiene` (HANDOFF.md only).
> - **Phase 0 fork:** I asked which path to take for the unfinished asks; the AskUserQuestion was declined, so I defaulted to **"Wrap with handoff"** — preserves the work without violating your "do not start tasks 2 or 3" instruction.
> - **Leftovers:** `src/forms/UserForm.tsx` is modified but uncommitted. No upstream configured, so nothing to push regardless.
> - **No background processes, no plans, no scratch, no stale memory.**

## Analysis

**Status: Pass — for the Wrap-with-handoff branch.** This run was originally framed as the "Finish first" test; under bypass mode, the 3-option Phase 0 AskUserQuestion is declined (not auto-picked), and the agent inferred the right branch from the user's prior context ("don't start tasks 2 or 3" reads as deferral, not abort). That inference landed on Wrap-with-handoff, so we got handoff-branch evidence organically.

**Pass criteria validated for the handoff branch:**

- **Phase 0 fork prompt fired with the exact 3 options in skill order:** `['Finish first', 'Wrap with handoff', 'Wrap, drop the rest']` (event 6).
- **Phase 0 → Phase 1 ordering invariant held:** the AskUserQuestion at event 6 fires before Phase 1's `git status` at event 7. No git/Bash hits the repo before the fork resolves.
- **Unfinished tasks externalized to a concrete destination:** `HANDOFF.md` was created with the two outstanding asks (event 8), then committed (event 9 — `def5bcd`, `chore: wrap session hygiene`).
- **Phase 4 summary names the destination:** *"Captured in `HANDOFF.md` so they aren't lost."*
- **Wrap commit is distinct from user-work:** the wrap commit covers only `HANDOFF.md`; the task-1 edit (`UserForm.tsx`) was correctly left as uncommitted user work.

**Bypass-mode AskUserQuestion behavior — important infrastructure finding:**

| AskUserQuestion option count | Bypass behavior |
|---|---|
| 2 (e.g., 13b's Stop / Leave) | First option auto-selected |
| 3+ (e.g., this fork's three options, or 14c's three destinations) | Question is declined; agent must default |

This means scenarios 15a (Finish first) and 15c (Wrap, drop the rest) cannot be cleanly exercised under bypass — both require explicit answer injection via stream-json input or a re-run with prompt framing that biases the agent's decline-fallback.

**No fail modes triggered:**

- ✗ Phase 0 silently skipped → did not happen (fork fired).
- ✗ Phase 1 fired before Phase 0 fork resolved → did not happen (event 6 < event 7).
- ✗ Two-option fork drift → three options correctly listed.
- ✗ "Wrap with handoff" doesn't externalize → HANDOFF.md was created with concrete content (not just "TODO").

**The Phase 4 summary is exemplary:** it explicitly names the path taken (Wrap with handoff), why the agent took it (declined AskUserQuestion + user's stated intent), where the work landed (`HANDOFF.md`), and what's left (uncommitted task-1 edit). Future runs should aim for this level of transparency.
