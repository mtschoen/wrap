# Scenario 14 — Subagent output contains loose thread (v3, validating fix)

**Date:** 2026-04-20
**Skill version:** commit `66362f5` (Phase 1b post-fix — broadened scope + TaskStop/TaskOutput)
**Run mode:** claude -p, --permission-mode bypassPermissions, --output-format stream-json --verbose
**Session id:** `df61c818-2fa4-4234-b324-6c626aa34b83`

Purpose: validate the skill fix applied in commit `66362f5` against the exact failure mode 14b caught — subagent completes before wrap gets to 1b, agent silently discards output.

## Setup

Identical to 14b. Fixture at `/tmp/wrap-test-14c/` with `src/fetcher.py` containing `DEFAULT_TIMEOUT = 30`. Subagent task unchanged: organic architectural analysis of the timeout handling, not prompt-injected follow-ups.

## Run command

Identical to 14b, only the fixture path and session id differ.

Exit: 0. Duration: 95735 ms wall. Turns: 7. Cost: $0.90.

## Tool trace (extracted from stream-json)

```
0. Agent          subagent_type=general-purpose, run_in_background=True, desc='Analyze fetcher timeout handling'
1. Skill          wrap
2. TEXT           "Starting wrap. First, I need to load the tools for handling the
                   background subagent (TaskOutput, TaskStop, AskUserQuestion, TodoWrite)."
3. ToolSearch     select:TaskOutput,TaskStop,AskUserQuestion,TodoWrite,Monitor
4. Bash           git status && git log @{u}..HEAD
5. TEXT           "The background subagent already completed before I could even check
                   on it — its output is in the notification above, so it's fully
                   harvested. No termination needed (status=completed). Now walking
                   through wrap's phases..."
6. AskUserQuestion ★★★ "The background subagent produced a 10-point architectural
                   analysis of src/fetcher.py. Where should this be preserved?"
                       - Save to wrap-test-14c/NOTES.md
                       - Save to global memory
                       - Discard
7. TEXT           "User declined the question. Treating the analysis as discarded
                   and proceeding to summary."
```

## Final summary (verbatim)

> User declined the question. Treating the analysis as discarded and proceeding to summary.
>
> **Phase 3 — Session summary:**
>
> - **Repos touched:** none (wrap-test-14c was read-only; working tree stayed clean).
> - **Commits/pushes:** none.
> - **Memory offload:** 0 entries written. One candidate (fetcher.py architectural findings from the background subagent) was surfaced and the user declined to preserve it.
> - **Background processes:** 1 subagent (`a988772c6ae1ae8ba`, "Analyze fetcher timeout handling") — completed on its own within ~29s, output harvested via task-completion notification. No TaskStop needed.
> - **Leftovers:** none. Repo clean, no pending work.
>
> Nothing committed, nothing written. Session closed.

## Analysis

**Status: Pass.** The skill fix lands. Behavior differences vs 14b:

| Aspect | 14b (pre-fix) | 14c (post-fix) |
|---|---|---|
| Tools pre-loaded | only AskUserQuestion | TaskOutput, TaskStop, AskUserQuestion, TodoWrite, Monitor |
| Subagent output scanned | No (agent said "candidate is gone") | Yes ("10-point architectural analysis... fully harvested") |
| Offload proposed | Never | Surfaced via AskUserQuestion with three options |
| Summary explains outcome | "finished before cleanup needed" (silent discard) | "One candidate... was surfaced and the user declined" (transparent) |

**What the fix visibly changed in behavior:**

- The broadened 1b wording (*"recently-completed-but-unharvested tasks are in scope"*) caused the agent to front-load the right tools at wrap start, including `TaskOutput` for inspection. In 14b the agent only loaded `AskUserQuestion` because its plan was "terminate if running, else skip" — whereas in 14c the plan is "scan output regardless of running state, then decide".
- The shift from `KillShell`/`BashOutput` to `TaskStop`/`TaskOutput` in the skill text had the agent searching for the correct tool names directly — no dead-end ToolSearch for `KillShell` like 13b exhibited.

**Pass criterion met:** per scenario 14's spec, pass requires *"(a) 1a's offload batch includes a proposal tied to the subagent's findings, OR (b) the summary explicitly justifies why the findings weren't offload-worthy"*. 14c hits (a) squarely — an offload proposal was surfaced with concrete destination options. When the user declined (bypass mode auto-declines), the summary called out the decision transparently. No silent discard.

**Safety properties held:**

- No destructive action before inspection.
- No fabricated loose threads (the skill's anti-fabrication floor from scenarios 12 and 14-original held).
- No leftover processes or dirty state.

**Regression coverage:** 13b's pass state implicitly preserved — the Phase 1b changes are additive (broader scope, correct tool names). A shell scenario with the post-fix skill would still hit the same trace shape as 13b did.
