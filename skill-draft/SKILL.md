---
name: wrap
description: Use when the user says /wrap, "wrap up", "close out this session", "finish the session", or otherwise signals intentional session end. Externalizes ephemeral working memory into durable artifacts and brings every touched repo into a clean state for the next session. Runs only when the user explicitly asks — never auto-runs from hooks.
---

# wrap

The session-closing ritual for a Claude Code session. Performs two equally-mandatory jobs: **externalize ephemeral working memory** (things the current agent knows from this conversation that no file/commit captures yet) into durable artifacts, and **bring every touched repo into a clean state** so the next session's agent doesn't waste cycles wading through obsolete context.

## When to use

- User types `/wrap` or says some variant of "wrap up this session", "close out", "let's finish for the day".
- User explicitly asks you to update memory / save learnings / commit everything before exit.
- `project-maintenance` is running and its procedure tells you to run wrap as step 0.

## When NOT to use

- User is exiting quickly to restart the session, reboot the machine, or context-switch. Some exits are quick exits; those are not wraps.
- No explicit wrap intent has been expressed. A `SessionEnd` reminder hook may nudge the user, but you do not invoke wrap yourself without explicit ask.
- During a mid-session auto-suggestion. Wrap is always intentional and user-initiated.

## Operating principles

1. **Memory offload first, hygiene second.** The headline job is externalizing what is about to be destroyed. Repo cleanup is equally mandatory but conceptually secondary: if memory offload fails for a repo, do not proceed to destructive cleanup in that repo.

2. **Portable and tool-agnostic.** Wrap works in any repo with or without `projdash`, with or without superpowers, on any platform. Describe what needs to happen in prose; let the available tools decide how.

3. **Always fan out.** One `/wrap` covers every repo the session touched, not just the current working directory. Use your own recall of which paths you edited + a dirty-scan cross-check + user confirmation.

4. **Looser delete semantics than `project-maintenance`.** Wrap may delete untracked files **with explicit per-item approval**. PM forbids untracked-file deletion entirely. This divergence is intentional: externalizing scratch and then cleaning it up is wrap's whole purpose.

5. **Extract loose threads before deleting anything.** Any plan, scratch file, or stale memory being removed must first be scanned for "we should fix X later" / "Y might come up again" thoughts, which go to durable destinations *before* the source is removed. See `references/plan-classification.md`.

6. **Stateless.** Wrap maintains no durable record of its own runs. Each invocation asks "what's true right now" and acts accordingly. Running `/wrap` twice in a row is safe — the second run finds nothing the first one already cleaned.

7. **Verify before delete.** Every finding surfaces with evidence, a recommendation, a confidence level, and the exact action on approval. The user approves batches via `AskUserQuestion`, not per-item unless explicitly described otherwise below.

8. **No items, no ceremony.** Each phase only runs its `AskUserQuestion` batch when its research has surfaced actual candidates. If a phase finds nothing, skip the prompt and continue. If *all* phases find nothing — including Phase 0's scope detection landing on a fully clean state — go straight to Phase 3 with a terse "nothing to wrap" summary. **Do not invent items out of nothing just to have something to do.** That is an explicit failure mode (see scenario 1 in `docs/pressure-scenarios.md`). Empty sweeps are a pass condition, not a problem to work around. Idempotent re-runs and clean-state invocations both look the same: detect nothing, summarize nothing, exit.

9. **Orchestrator retains override authority.** Parts of Phase 2 fan out to per-repo sonnet subagents to keep verbose tool output (file reads, status walls, plan-file contents) out of main context. The orchestrator (this conversation) is still in charge: it may at any time read repo contents directly, bypass a subagent's draft, or pull per-repo work back into main context if subagent output feels thin, suspicious, or incomplete. Subagents are an optimization, not a delegation contract. The judgment-heavy work — deciding what's worth saving, reviewing drafts, assembling user-approval batches, writing the final summary — stays with the orchestrator.

## Procedure

Wrap runs four phases in strict sequence (0 → 1 → 2 → 3) — but they are independently fault-tolerant. A failure in phase N does not undo phases 1..N-1, and (for most failures) does not abort phases N+1..last. Phase 3 (the summary) always runs, even after cancellation or failure.

The orchestrator runs Phases 0, 1, 2a, and 2d directly. Phases 2b and 2c fan out to per-repo subagents (see "Subagent dispatch" below). Phase 3 stitches subagent fragments together with the orchestrator's cross-repo narrative.

### Phase 0 — Detect scope

Determine which repos the session touched. In order of precedence:

1. **Recall.** Review the conversation and list every path you edited, created, or ran git commands against. This is the primary source of truth.
2. **Dirty-scan cross-check.** For each recalled path (and its parent repos), check whether the working tree is dirty or has unpushed commits. Use whatever dirty-detection tooling is available — if `projdash` MCP tools are present, use them; otherwise run `git status` and `git log @{u}..HEAD` directly.
3. **Confirm with the user.** Present the detected repo list as a single batch via `AskUserQuestion`: *"I'll wrap these repos: [list]. Add or remove any?"*

**Not in scope:** Repos the session only *read*. Reading is not touching.

**Output of Phase 0:** An ordered list of touched-repo roots. Store it in working memory for Phases 1–3.

### Phase 1 — Session-wide sweep

Cross-cutting things not tied to any one project. Only done once per wrap, before per-repo work begins. Two sub-phases: memory offload, then background process sweep. Both run in the orchestrator's main context — they are intrinsically conversation-bound and don't benefit from subagent isolation.

**1a. Memory offload.**

1. Review your conversation context (plus the on-disk transcript at `~/.claude/projects/<slug>/<session-id>.jsonl` if your context has been compacted and you need to recover earlier content). Include recent output from any background shells or subagents (read via `TaskOutput` or the platform equivalent) — loose threads hiding in their output count, including output from tasks that completed during the session but whose results you never explicitly harvested.
2. Walk the **cross-project categories** section of `references/categories.md` in order. For each category, ask yourself *"is there anything in this category from this session worth saving?"* and draft candidate items.
3. Each draft item is a concrete: what to save, where to save it, and why.
4. Surface the full set as a single `AskUserQuestion` batch. Let the user approve, edit, or reject the whole set.
5. Execute the approved writes — create or update memory files, modify `MEMORY.md` index entries, etc.

**Checklist-driven:** Walk every category even if you think it is empty. Quiet sessions should not silently skip memory offload.

**1b. Background process sweep.**

Explicitly terminate anything this session started in the background before declaring the session closed. The harness *may* reap these on process exit, but that behavior is undocumented — explicit shutdown gives predictable results and a clean summary line.

1. Background Bash shells (`run_in_background: true`) — the platform treats these as tasks. Read their output (e.g. via `TaskOutput`) before stopping them.
2. Task/Agent subagents (`run_in_background: true`) — same rule: read output first, *then* terminate. **Recently-completed-but-unharvested tasks are in scope** — a subagent that finished 2 seconds ago is as much a source of ephemeral findings as one still mid-run. Do not skip the scan just because the task is no longer running; what matters is whether its output has been absorbed yet.
3. Active `Monitor` watchers — cancel each.

Surface the full set (running and recently-completed-but-unharvested) as a single `AskUserQuestion` batch with per-item context (what it is, how long it has been running or how recently it completed, last output line or final summary). If inspecting any surfaces a new loose thread, loop back and amend the 1a offload batch before terminating. Use the platform's task-stop tool (e.g. `TaskStop`, which currently handles both background shells and subagents uniformly) to terminate. If nothing is running or unharvested, skip silently — per principle 8, no ceremony.

This sweep does *not* terminate the wrap subagents dispatched in Phase 2; those are part of the wrap and finish on their own.

### Phase 2 — Per-repo work

Phase 2 covers per-repo memory offload (2a), plans sweep (2b), hygiene pass (2c), and the per-repo commit/push prompt (2d). The orchestrator does 2a directly across all touched repos. 2b and 2c fan out to per-repo sonnet subagents (with a bucketing cap). The orchestrator reviews their findings, runs one combined `AskUserQuestion` batch, and either executes inline or dispatches sonnet executors. 2d returns to the orchestrator for the user-facing commit prompt.

**Per-repo independence rule:** if any sub-phase fails partway through a repo, record the failure in the running Phase 3 summary, skip remaining sub-phases for *that* repo (especially never push if commit failed), and continue to the next repo. Do not abort the whole wrap.

**Skip-fan-out option:** If a repo's expected 2b/2c work is trivially small (e.g. one or two files, no plans, no scratch), the orchestrator may skip the subagent dispatch and do 2b/2c inline. Subagent dispatch has fixed first-turn cost; for tiny work it can exceed the savings. Use judgment.

**2a. Per-repo memory offload (orchestrator, all repos sequentially).**

For each repo in the Phase 0 list, walk the **per-project categories** section of `references/categories.md` and draft candidate items in the orchestrator's main context — project learnings, decisions, CLAUDE.md updates, gotchas. This step has no verbose tool output: it is recall-driven drafting against the conversation context already loaded. Subagent isolation buys nothing here, and the nuance cost of fanning it out outweighs the savings.

The 2a drafts are not yet executed or shown to the user. Hold them in working memory; they are combined with 2b/2c findings before the AskUserQuestion batch in the per-repo review step below. The drafts are also passed into each subagent's brief as cross-reference material so subagents don't duplicate them.

**2b + 2c. Plans sweep + hygiene pass (per-repo subagents).**

After 2a is complete for all touched repos, dispatch per-repo subagents (model: sonnet) to do 2b and 2c work in their own contexts. Each subagent reads `references/plan-classification.md` and `references/hygiene-checklist.md` on demand — those references are not loaded into the orchestrator's context.

**Bucketing.** Cap at 4 subagents to avoid first-turn cache-miss overhead. The most-edited repo (where the bulk of the session's work happened) gets its own subagent. Remaining repos are bucketed by weight; a subagent assigned multiple light repos still wins on cost because it does the verbose tool work in its own context, just sequentially across its assigned repos.

**Brief structure.** The Agent tool's prompt is the only channel from orchestrator to subagent. Load it with session-grounded pointers rather than expecting the subagent to rediscover them. A few sharp pointers beats an exhaustive briefing — too much in the prompt dilutes attention.

For each subagent (per repo or per bucket), the prompt should include:

1. **Why this repo is in scope** — one sentence from the orchestrator's recall, e.g. *"This session refactored the auth middleware and added two new test files; that's why this repo is in the wrap."*
2. **Pre-flagged hotspots** — specific files, plan paths, or directories the orchestrator already half-noticed and wants the subagent to look at first, e.g. *"Pay particular attention to `plans/auth-rewrite.md` (likely completed this session), the untracked `notes/scratch-2.md` (looks like loose-thread material), and check whether `CLAUDE.md` mentions the deprecated `validateSession` helper — we removed it."* This is the "leading content" that converts the subagent from "explore cold" to "verify these specific suspicions and surface anything else nearby."
3. **2a drafts already produced for this repo** — so the subagent can cross-reference and not duplicate, e.g. *"The orchestrator has already drafted these per-project memory items: [list]. If your 2b/2c findings overlap, flag the duplication rather than re-drafting."*
4. **What to do** — *"Follow `references/plan-classification.md` for 2b and `references/hygiene-checklist.md` for 2c. Return findings (not actions) — the orchestrator will assemble the user-approval batch and dispatch executors after approval."*
5. **Return schema** — match `references/finding-schema.md`. Also include a short repo-level summary fragment (commits expected, plans found by state, hygiene findings count) for Phase 3 to stitch into the final summary.

**Review and combine.** When subagents return, the orchestrator reviews each subagent's findings against its own knowledge of the session. This is the natural choke point where opus's judgment earns its keep:

- *"Did the subagent miss something I noticed during the session?"* — if yes, add it.
- *"Is this finding actually worth surfacing, or is it noise?"* — drop noise.
- *"Does this classification feel right given how the session actually went?"* — override if not.

If a subagent's findings feel thin, generic, or wrong, the orchestrator may bypass them entirely (principle 9): read the repo directly, do 2b/2c inline for that repo, and produce its own findings. This is a first-class option, not an emergency escape.

After review, combine 2a drafts + reviewed 2b/2c findings into one `AskUserQuestion` batch per repo (or batched across repos if total volume is small). Get approval.

**Execution.** After approval, execution can stay in the orchestrator (small/single-repo cases) or fan back out to sonnet executor subagents (large or multi-repo cases). Executors receive the approved findings + their `action_on_approval` strings, and report what they actually did. Auto-commit (commit #1 in 2d) happens in the repo where the writes landed, regardless of who executed them.

Critical: destructive actions in 2c gate on 2a + 2b having completed successfully for this repo. If memory offload or plans sweep failed or was cancelled, skip 2c's destructive items too (still show the read-only summary in the final report).

**2d. Commit + push decision (orchestrator).**

This sub-phase produces **two separate commits** (at most) per repo, in this order: first wrap's own edits auto-commit, then the user-work prompt runs. Never combine them — they must be distinguishable in git history.

**Wrap's own edits (commit #1, automatic).** Everything wrap wrote during 1, 2a, 2b, 2c (memory updates, CLAUDE.md edits, archived plans, deleted scratch) auto-commits in one commit per repo with this message format:

```
chore: wrap session hygiene

- <one bullet per category of change, e.g. "Archived 2 completed plans">
- <e.g. "Updated CLAUDE.md with 3 new project facts">

Wrap-Session-Id: <current session id if known, else a timestamp>
```

The `Wrap-Session-Id:` trailer lets future tooling distinguish wrap commits from user work.

**User work (commit #2, prompted).** Uncommitted changes that existed *before* wrap started. After wrap's own commit lands, show `git status` + `git log @{u}..HEAD` and ask the user per repo:

> `(p)ush (commit + push) / (c)ommit only / (s)tash / (l)eave as-is / (b)ranch-off-and-commit`

Rules for this prompt:

- Never pick an option for the user.
- Never push without the explicit `(p)ush` choice.
- Never force-push. If the push is rejected as non-fast-forward, report "push rejected, commits stay local" and continue.
- `(b)ranch-off-and-commit` creates a new branch from current HEAD, commits there, leaves `main`/the original branch untouched.
- If there is no upstream, `(p)ush` degrades to `(c)ommit only` for that repo; inform the user.

### Phase 3 — Session summary

Always runs, even on cancel or abort. Subagents return short repo-level summary fragments as part of their Phase 2 output (commits made, plans closed, hygiene findings, leftovers per repo); the orchestrator stitches the fragments together and adds the cross-repo narrative no individual subagent has the context to write — the session's overall arc, what's still hanging across repos, what feels worth flagging for next time.

The summary covers:

- **Accomplishments per repo:** commits made this session, files touched, plans closed, loose threads captured. (Subagent fragments slot in here.)
- **Memory offload totals:** how many entries written, to which destinations (grouped by memory type).
- **Session-wide cleanup:** background shells killed, subagents stopped, monitors cancelled (counts + one line each). Omit the bullet entirely if 1b found nothing.
- **Rejected or flagged:** anything the agent surfaced that the user declined, and anything explicitly flagged as needing human judgment.
- **Leftovers:** per-repo, what is still dirty, unpushed, or in-progress after the wrap. Naming each explicitly so the user can decide whether to come back to it.

Spot-check before publishing: cross-reference subagent fragments against `git log` and the actual state on disk. Subagents occasionally over-claim what they accomplished; an opus pass to verify "did the subagent actually do what it reported?" is part of the summary's quality. If a discrepancy turns up, correct the summary and note the discrepancy.

Keep the summary terse — specific numbers, specific paths, specific decisions. No filler.

**Empty case:** If Phases 0–2 found nothing (clean state, idempotent re-run, or genuinely-quiet session), the entire summary is one or two lines: *"Nothing to wrap. \<repo names\> are clean, no memory items to offload, no background processes running."* Do not pad with bullet points for empty categories. Per principle 8, the empty path is a valid pass — emit it directly and exit.

## Failure handling

- **Phase independence:** failure in phase N leaves phases 1..N-1 intact and continues to phase N+1. Phase 3's summary records what completed and what didn't.
- **Per-repo independence inside Phase 2:** repo-level failures are logged and wrap moves to the next repo.
- **Subagent failure / timeout:** treat as "no findings for this bucket." The orchestrator may fall back to doing 2b/2c directly for the affected repos (principle 9), or skip with a note in the Phase 3 summary. Never silently lose a repo from the wrap.
- **Subagent over-claim:** if Phase 3's spot-check finds a subagent reported a commit / write / deletion that didn't actually happen, correct the summary and execute the missing action inline if still appropriate.
- **Destructive-action gate:** deletes and archives run only after memory offload succeeds for that repo.
- **User cancel (`Ctrl+C` / stop):** whatever was already approved + executed stays done. Print a "cancelled — completed: X / pending: Y" summary immediately. Cancellation also stops any in-flight subagents — wrap does not leave wrap-spawned subagents running after the user cancels.
- **Git errors:**
  - Merge conflict on wrap's auto-commit → stash wrap's edits, leave user work alone, record the conflict in the summary.
  - Non-fast-forward push rejection → never force-push; report and continue.
  - No upstream → treat as "commit only, no push" and continue.
- **Untracked deletions** — always per-item approval. Each approval logged in the summary with the full path. Rejections logged with the reason.
- **Idempotent re-run** — running `/wrap` twice in a row is safe. Second run finds nothing unless new state appeared between runs.

## References

- `references/categories.md` — memory-offload category checklist for Phases 1 and 2a.
- `references/plan-classification.md` — plan-file classifier + the extract-loose-threads-first safety rule for Phase 2b. Loaded by the per-repo subagent that handles 2b, not by the orchestrator.
- `references/hygiene-checklist.md` — Phase 2c items with research notes per check. Loaded by the per-repo subagent that handles 2c.
- `references/finding-schema.md` — the shape of a finding and of the summary's action log (copied from `project-maintenance`, divergence OK). Loaded by both orchestrator and subagents.
- `references/session-end-reminder.md` — spec for the decoupled `SessionEnd` nudge hook. Wrap does not read or touch the hook's marker file; it is a separate system.

## Companion scripts

User-facing utilities shipped alongside the skill. Not invoked during the wrap procedure itself.

- `scripts/find-unwrapped.sh` (bash) and `scripts/find-unwrapped.ps1` (PowerShell) — list recent Claude Code sessions that did NOT end with `/wrap`. Useful for recovering after a crash, a culled `claude` process, or just answering *"did I leave anything dangling?"*. Defaults filter to sessions newer than the wrap-skill's first commit, ≥50 KB, excluding `wrap-test*` scratch projects. Run with `--help` (bash) or `Get-Help` (PS) for full options.
