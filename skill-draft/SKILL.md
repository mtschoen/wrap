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

## Procedure

Wrap runs four phases in strict sequence (0 → 1 → 2 → 3) — but they are independently fault-tolerant. A failure in phase N does not undo phases 1..N-1, and (for most failures) does not abort phases N+1..last. Phase 3 (the summary) always runs, even after cancellation or failure.

### Phase 0 — Detect scope

Determine which repos the session touched. In order of precedence:

1. **Recall.** Review the conversation and list every path you edited, created, or ran git commands against. This is the primary source of truth.
2. **Dirty-scan cross-check.** For each recalled path (and its parent repos), check whether the working tree is dirty or has unpushed commits. Use whatever dirty-detection tooling is available — if `projdash` MCP tools are present, use them; otherwise run `git status` and `git log @{u}..HEAD` directly.
3. **Confirm with the user.** Present the detected repo list as a single batch via `AskUserQuestion`: *"I'll wrap these repos: [list]. Add or remove any?"*

**Not in scope:** Repos the session only *read*. Reading is not touching.

**Output of Phase 0:** An ordered list of touched-repo roots. Store it in working memory for Phases 1–3.

### Phase 1 — Session-wide sweep

Cross-cutting things not tied to any one project. Only done once per wrap, before the per-repo loop. Two sub-phases: memory offload, then background process sweep.

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

### Phase 2 — Per-repo loop

For each touched repo in the Phase 0 list, in order, run sub-phases 2a→2b→2c→2d. Finish one repo before starting the next.

Per-repo independence rule: if any sub-phase fails partway through a repo, record the failure in the running Phase 3 summary, skip remaining sub-phases for *that* repo (especially never push if commit failed), and continue to the next repo. Do not abort the whole wrap.

**2a. Per-repo memory offload.**

Walk the **per-project categories** section of `references/categories.md` for this specific repo. Draft candidate items — project learnings, decisions, CLAUDE.md updates, gotchas. Surface as a batch, get approval, execute.

**2b. Plans / specs sweep.**

Follow `references/plan-classification.md`:

1. Scan all usual plan locations in the repo.
2. Classify each plan file as completed / superseded / abandoned / in-progress / draft.
3. **Extract loose threads from every plan being removed, before removing it.** This is non-negotiable.
4. After extraction is approved and executed, apply the action-per-state table: delete tracked+stale outright, ask-with-bias-to-delete for untracked, archive abandoned, keep in-progress and drafts.

**2c. Hygiene pass.**

Follow `references/hygiene-checklist.md`. For each item in the checklist, research candidate findings, surface them with evidence + recommendation + action-on-approval, batch-approve, execute.

Critical: destructive actions in 2c gate on 2a + 2b having completed successfully for this repo. If memory offload or plans sweep failed or was cancelled, skip 2c's destructive items too (still show the read-only summary in the final report).

**2d. Commit + push decision.**

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

Always runs, even on cancel or abort. Produce a short natural-language summary covering:

- **Accomplishments per repo:** commits made this session, files touched, plans closed, loose threads captured.
- **Memory offload totals:** how many entries written, to which destinations (grouped by memory type).
- **Session-wide cleanup:** background shells killed, subagents stopped, monitors cancelled (counts + one line each). Omit the bullet entirely if 1b found nothing.
- **Rejected or flagged:** anything the agent surfaced that the user declined, and anything explicitly flagged as needing human judgment.
- **Leftovers:** per-repo, what is still dirty, unpushed, or in-progress after the wrap. Naming each explicitly so the user can decide whether to come back to it.

Keep the summary terse — specific numbers, specific paths, specific decisions. No filler.

**Empty case:** If Phases 0–2 found nothing (clean state, idempotent re-run, or genuinely-quiet session), the entire summary is one or two lines: *"Nothing to wrap. \<repo names\> are clean, no memory items to offload, no background processes running."* Do not pad with bullet points for empty categories. Per principle 8, the empty path is a valid pass — emit it directly and exit.

## Failure handling

- **Phase independence:** failure in phase N leaves phases 1..N-1 intact and continues to phase N+1. Phase 3's summary records what completed and what didn't.
- **Per-repo independence inside Phase 2:** repo-level failures are logged and wrap moves to the next repo.
- **Destructive-action gate:** deletes and archives run only after memory offload succeeds for that repo.
- **User cancel (`Ctrl+C` / stop):** whatever was already approved + executed stays done. Print a "cancelled — completed: X / pending: Y" summary immediately.
- **Git errors:**
  - Merge conflict on wrap's auto-commit → stash wrap's edits, leave user work alone, record the conflict in the summary.
  - Non-fast-forward push rejection → never force-push; report and continue.
  - No upstream → treat as "commit only, no push" and continue.
- **Untracked deletions** — always per-item approval. Each approval logged in the summary with the full path. Rejections logged with the reason.
- **Idempotent re-run** — running `/wrap` twice in a row is safe. Second run finds nothing unless new state appeared between runs.

## References

- `references/categories.md` — memory-offload category checklist for Phases 1 and 2a.
- `references/plan-classification.md` — plan-file classifier + the extract-loose-threads-first safety rule for Phase 2b.
- `references/hygiene-checklist.md` — Phase 2c items with research notes per check.
- `references/finding-schema.md` — the shape of a finding and of the summary's action log (copied from `project-maintenance`, divergence OK).
- `references/session-end-reminder.md` — spec for the decoupled `SessionEnd` nudge hook. Wrap does not read or touch the hook's marker file; it is a separate system.
