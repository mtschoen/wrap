# /wrap Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/wrap` skill end-to-end — scaffolding, prose, hook scripts, pressure tests, deployment, `project-maintenance` integration, and GitHub publishing.

**Architecture:** A tool-agnostic prose skill at `~/skills-dev/wrap/` following the user's established skills-dev pattern (`skill-draft/` as source of truth, deployed to `~/.claude/skills/wrap/`, published to GitHub). Four-phase runtime structure: detect scope → session-wide memory offload → per-repo loop (offload + plans + hygiene + commit) → summary. A decoupled `SessionEnd` hook script provides a rate-limited nudge reminder. `project-maintenance` is updated to delegate its per-session-hygiene slice to wrap.

**Tech Stack:** Markdown (skill prose + references), Bash + PowerShell (hook scripts), git, gh CLI (publishing), update-config skill (hook registration).

**Source of truth for design decisions:** `docs/specs/2026-04-11-wrap-design.md` in this repo. When a decision is not spelled out in this plan, defer to the spec.

**Working directory for all tasks:** `~/skills-dev/wrap/` unless otherwise noted.

**Windows note:** Commands in this plan assume Unix-style shells (bash via Git Bash is fine on Windows). Use forward slashes in paths. PowerShell is only used inside `session-end-reminder.ps1` itself.

---

## Task 1: Create top-level scaffolding files

**Files:**
- Create: `README.md`
- Create: `AUDIT.md`

- [ ] **Step 1: Create `README.md` with the following exact content**

```markdown
# wrap

A Claude Code skill that runs the session-closing ritual: externalizes ephemeral working memory into durable artifacts, then brings every touched repo into a clean state for the next session.

See `docs/specs/2026-04-11-wrap-design.md` for the full design rationale.

## Status

Under development. Tracked pressure-test results in `AUDIT.md`.

## Install

1. Copy `skill-draft/` contents to `~/.claude/skills/wrap/`.
2. Register the `SessionEnd` hook in `~/.claude/settings.json` — use the `update-config` skill, pointing it at `hooks/session-end-reminder.sh` (Unix/macOS) or `hooks/session-end-reminder.ps1` (Windows).

## Invocation

Type `/wrap` at the end of a session when you are ready to close out. Wrap is always intentional — it never auto-runs.
```

- [ ] **Step 2: Create `AUDIT.md` with the following exact content**

```markdown
# Wrap Skill Audit Log

Pressure-test results rolled up from `docs/evidence/`. Each scenario from `docs/pressure-scenarios.md` gets a row when it has been run.

| Scenario | Status | Evidence | Notes |
|---|---|---|---|
| _(none run yet)_ | | | |
```

- [ ] **Step 3: Commit**

```bash
cd ~/skills-dev/wrap
git add README.md AUDIT.md
git commit -m "Scaffold README and AUDIT"
```

---

## Task 2: Create the skill-draft directory layout and reference files

**Files:**
- Create: `skill-draft/references/finding-schema.md` (copy from PM)
- Create: `skill-draft/references/categories.md`
- Create: `skill-draft/references/plan-classification.md`
- Create: `skill-draft/references/hygiene-checklist.md`
- Create: `skill-draft/references/session-end-reminder.md`

- [ ] **Step 1: Create skill-draft directories**

```bash
cd ~/skills-dev/wrap
mkdir -p skill-draft/references
```

- [ ] **Step 2: Copy `finding-schema.md` from project-maintenance**

```bash
cp ~/skills-dev/project-maintenance/skill-draft/references/finding-schema.md skill-draft/references/finding-schema.md
```

Verify the copy succeeded:

```bash
head -3 skill-draft/references/finding-schema.md
```

Expected output: the heading `# Finding Schema` followed by the schema preamble. If this fails because the source doesn't exist, fall back to reading `~/.claude/skills/project-maintenance/references/finding-schema.md` instead.

- [ ] **Step 3: Create `skill-draft/references/categories.md` with exact content**

```markdown
# Memory Offload Categories

The checklist the agent walks during Phase 1 (session-wide offload) and Phase 2a (per-repo offload). For each category, the agent asks itself *"is there anything in this category from this session?"* and proposes items if so.

## Cross-project categories (Phase 1 only)

These are handled once per wrap invocation, not per repo.

### User preferences discovered

New gotchas, likes, dislikes, or working styles the user expressed during the session.

- **Destination:** `~/.claude/projects/.../memory/feedback_*.md` — one file per rule, with frontmatter (`name`, `description`, `type: feedback`).
- **Why:** Future conversations should not need the user to repeat themselves.
- **Examples:** "user prefers one bundled PR over small ones for refactors", "don't auto-push without asking".

### User profile updates

New facts about who the user is, what they do, what hardware/tools they use.

- **Destination:** `~/.claude/projects/.../memory/user_*.md`.
- **Examples:** new machine, new role, new language they're learning.

### External references

Docs, URLs, dashboards, Slack channels, or external systems the user pointed at during the session and will want again.

- **Destination:** `~/.claude/projects/.../memory/reference_*.md`.
- **Examples:** "the oncall dashboard is at grafana.internal/...", "pipeline bugs go in Linear project INGEST".

### Cross-project learnings

Patterns that apply to multiple projects — tool behaviors, language gotchas, best practices the user reinforced.

- **Destination:** `~/.claude/projects/.../memory/` (pick the closest existing type — feedback / reference / user).
- **Example:** "on Windows, git rename defaults to master; rename to main immediately".

## Per-project categories (Phase 2a only)

These run once per touched repo inside Phase 2's loop.

### Learnings about a codebase

Things the agent figured out about the project — where X lives, why Y is structured that way, what Z actually does.

- **Destination:** project `CLAUDE.md` or `AGENTS.md` if the learning is short and general; project memory otherwise.
- **Example:** "the `scanner/` module does both discovery and metadata — adapters are the read+write layer".

### Decisions + rationale

Choices the agent + user made during the session that future agents will need to understand.

- **Destination:** commit message (preferred), plan file, or memory entry.
- **Example:** "we rejected option B because the locking behavior broke concurrent writes".

### Unfinished plans

Plan files, specs, or designs that were started but not completed in this session.

- **Destination:** `docs/superpowers/specs/` / `PLAN.md` / `.plans/` — whichever convention the project already uses.
- **Note:** If the plan was only discussed verbally in the conversation and never written down, wrap should offer to materialize it as a plan file.

### Open TodoWrite items

The current session's TodoWrite list contains items that should persist.

- **Destination:** `PLAN.md` or a new plan file under `docs/superpowers/specs/`.
- **Note:** The TodoWrite list itself is session-scoped and will be lost. Wrap must externalize it before session end.

### Project facts / context

Deploy targets, build times, known quirks, environment constraints specific to this project.

- **Destination:** project memory or `CLAUDE.md`.
- **Example:** "builds take ~12 minutes on CI, run `pytest -x` locally for fast iteration".

### Gotchas / pitfalls hit

Things that went wrong during the session that future agents should avoid.

- **Destination:** `CLAUDE.md` note or code comment at the site.
- **Example:** "tests fail silently if `ASYNC_MODE=1` is not set; check env before debugging".

### Work-in-progress code

Uncommitted changes discussed but not finished.

- **Destination:** commit as WIP or stash with a descriptive note. Decided in Phase 2d (commit decision).
```

- [ ] **Step 4: Create `skill-draft/references/plan-classification.md` with exact content**

```markdown
# Plan Classification

How to classify plan files during Phase 2b (plans sweep), and the safety rule that must precede any deletion.

## Where to look

Scan every repo in scope for plan-like files under any of these paths:

- `docs/superpowers/specs/*.md`
- `docs/superpowers/plans/*.md`
- `docs/specs/*.md` / `docs/plans/*.md`
- `PLAN.md` / `TODO.md` at repo root
- `.plans/*.md` if the directory exists
- Any in-conversation draft the agent remembers creating but not saving

## Classification states

For each file found, determine its state:

| State | Evidence to look for | Example |
|---|---|---|
| **Completed** | Code referenced in the plan is merged/pushed. Checkboxes all ticked. Commit history includes the plan's closing work. | A plan for "add auth module" where `src/auth/` exists and tests are green. |
| **Superseded** | A newer plan covers the same ground, or the approach was reversed. | Two plans on the same topic with overlapping file lists; keep the newer one. |
| **Abandoned** | No progress for weeks. Mentioned in past conversations as "not doing that anymore." No code changes against it. | A plan last touched 6 weeks ago with no commits tying back to it. |
| **In progress** | Active work. Uncommitted changes sit against files the plan names. Recent commits tie back. | Dirty tree + plan referenced by the current session's work. |
| **Draft / not started** | Created but no work against it yet. Intentional deferral, not abandonment. | A plan file exists; git log shows only the creation commit. |

## The "extract loose threads first" safety rule

**Before any plan file is deleted or archived, the agent must scan its content for loose threads and externalize them first.** This rule is non-negotiable and is the main reason wrap is trusted to delete files at all.

### What counts as a loose thread

Any sentence or bullet in the plan that expresses:

- An unresolved question ("do we need X?", "unclear how Y handles Z")
- A future intention ("we should fix that later", "come back to this once Q lands")
- A warning or pitfall ("watch out for W", "don't forget that…")
- An idea or option that wasn't taken but might be revisited ("alternative: …", "could also …")
- A cross-reference to an incomplete area of the project ("this depends on the auth rewrite")

### Where loose threads go

- Unresolved questions + future intentions that are user-preference-shaped → memory (feedback or reference type)
- Warnings or pitfalls tied to a specific file/function → inline code comment OR `CLAUDE.md` note
- Alternatives considered → commit message trailer on the deletion commit, so git history preserves them
- Cross-references to other work → a new smaller plan file OR GitHub issue, never left dangling

### Order of operations

1. Read the plan file in full.
2. Emit candidate loose threads as a list, with proposed destinations.
3. Get user approval on the whole list (batch).
4. Execute the externalization (write the memory, edit CLAUDE.md, open the issue, etc.).
5. **Only now** delete or archive the source plan.

If the loose-thread extraction is rejected or fails, the source plan stays. Skipping step 3 or 4 is a bug.

## Actions per state (post-extraction)

| State | Action |
|---|---|
| **Completed + tracked in git** | Delete outright (`rm` + commit). Git history preserves the file for recovery. |
| **Completed + untracked** | Ask with bias-to-delete. Show path + first few lines + "delete? [Y/n]". |
| **Superseded** | Delete. Commit message notes which plan superseded it. |
| **Abandoned** | Archive — move to `<plan-dir>/archive/` (create if needed), not delete. Add a one-line note to the file's frontmatter: `status: abandoned, YYYY-MM-DD`. |
| **In progress** | Keep untouched. Optionally add a status frontmatter tag if the plan doesn't already have one. |
| **Draft / not started** | Keep. This is intentional deferral, not cruft. |
```

- [ ] **Step 5: Create `skill-draft/references/hygiene-checklist.md` with exact content**

```markdown
# Phase 2c Hygiene Checklist

The per-session-hygiene items that run once per touched repo during Phase 2c. Each item produces zero or more findings; findings follow the shape in `finding-schema.md`.

**Important scope rule:** These items are the *wrap-scope* subset of hygiene. Rare-tier items (master→main, CLAUDE/AGENTS merge, missing README/LICENSE, dead code, large files, disk warnings) are **not** wrap's job — they live in `project-maintenance`. Do not expand this checklist to include them.

## Items

| Check | What to look for | Research required |
|---|---|---|
| Uncommitted changes | `git status --porcelain` non-empty | Categorize files by whether wrap itself made the edit or the user did. Wrap's own edits auto-commit in Phase 2d; user edits get the user prompt. |
| Unpushed commits | `git log @{u}..HEAD` non-empty (if upstream exists) | List the commits with their subjects so the user sees what would be pushed. |
| Temp files — tracked | File matches `*.tmp`, `*.bak`, `scratch*`, or was added as a "scratch" commit | Run `git log -- <path>` to see why it was added. If the work has landed in permanent files, propose delete (recoverable from git). |
| Temp files — untracked | Same name patterns, not in git | Read the contents. If the scratch is spent, propose delete with per-item approval. Never bulk-approve untracked deletions. |
| Stale memory entries (project-scoped) | Entries in `~/.claude/projects/.../memory/project_*.md` or the project's own memory store that reference fixed issues, dangling files, or superseded decisions | Semantic check against current code. If a claim in the memory is no longer true, propose deletion with evidence (commit/line that invalidated it). |
| Merged local branches | `git branch --merged main` (excluding `main` itself) | Verify each branch is actually merged, not just name-matched. Propose pruning with `git branch -d`. |
| Stale worktrees (this session only) | Worktrees created during the session that are no longer needed | Wrap should only touch worktrees it has clear evidence the current session created. Inherited worktrees are untouched. |
| `.claude/scripts/` one-offs | Any files present in `.claude/scripts/` | Per the user's CLAUDE.md rule, one-offs should be deleted after use unless explicitly kept. Ask per file. |

## Operating rules (reused from PM)

1. **Verify before delete.** Never delete untracked files without per-item approval. Tracked files may be deleted only when (a) the working tree is otherwise clean and (b) the agent can state why the file has served its purpose.
2. **Research before asking.** Every finding surfaces with evidence, a recommendation, a confidence level, and the exact action on approval. The user should be able to y/n without opening files themselves.
3. **Log everything.** Every automated action, every user-approved action, and every user-rejected proposal appears in the final summary (Phase 3). Nothing invisible.

## Relationship to PM

Wrap's hygiene checklist is a *subset* of PM's former checklist. Do not duplicate items that have been explicitly moved to PM's rare-tier audit. If a user runs PM, PM runs wrap first, then does its own rare-tier checks on top. The two checklists must not overlap.

## Tooling

Follow tool-agnostic guidance: describe *what* to check in prose. The agent picks the best available implementation — projdash MCP tools if present (e.g. functions that front-load dirty detection and stale-memory scanning), raw git/grep/find otherwise.
```

- [ ] **Step 6: Create `skill-draft/references/session-end-reminder.md` with exact content**

```markdown
# SessionEnd Reminder Hook

A decoupled nudge mechanism, separate from the wrap skill itself. Registered as a `SessionEnd` hook in `~/.claude/settings.json`, runs at session exit, prints at most one line, exits 0.

## What it does

Checks the session's final `cwd` for wrap-worthy signals:

1. Working tree dirty? (`git status --porcelain` non-empty)
2. Unpushed commits? (`git log @{u}..HEAD` non-empty, if upstream exists)
3. Any files present in `.claude/scripts/`?

If any fire, prints a single-line reminder. Otherwise prints nothing.

## Rate limiter

A marker file at `~/.claude/wrap-nudge-last-fired`. If the hook fired within the last 5 minutes, the hook skips entirely (prevents noise during quick-exit-restart cycles). On each non-skipped run, the hook touches the marker.

**Wrap itself does not read or write this file.** Full decoupling — the skill and the hook know nothing about each other.

## Output format

Example:
```
⚠ wrap-worthy state: 3 dirty files, 2 unpushed commits in ~/llamalab. Consider /wrap next session.
```

If no signals fire, the hook prints nothing. Silent is valid.

## Scope caveat

The hook sees only the session's final `cwd`. If the session touched multiple repos but exited from a third, the hook only reports that third. This is acceptable because the hook is a nudge, not a checklist — the user knows what they touched.

## Settings.json example

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "command": "~/.claude/skills/wrap/hooks/session-end-reminder.sh"
      }
    ]
  }
}
```

On Windows, substitute `session-end-reminder.ps1`:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "command": "pwsh -NoProfile -File C:/Users/<you>/.claude/skills/wrap/hooks/session-end-reminder.ps1"
      }
    ]
  }
}
```

Use the `update-config` skill to perform the registration rather than hand-editing `settings.json`.

## What the hook must NOT do

- Invoke wrap. It is a nudge, not a trigger.
- Block or delay exit. Must return within milliseconds and exit 0 always.
- Read wrap's internal state. Wrap is stateless; the hook is rate-limited independently.
- Check multiple repos. Single-repo (final `cwd`) is the intentional scope.
```

- [ ] **Step 7: Verify all five reference files exist**

```bash
ls skill-draft/references/
```

Expected output: `categories.md  finding-schema.md  hygiene-checklist.md  plan-classification.md  session-end-reminder.md`

- [ ] **Step 8: Commit**

```bash
git add skill-draft/references/
git commit -m "Add wrap skill reference files"
```

---

## Task 3: Write the main SKILL.md

**Files:**
- Create: `skill-draft/SKILL.md`

This is the main prose file the agent reads when `/wrap` is invoked. Keep it tool-agnostic — describe actions in prose, never name specific MCP functions or CLI tools as required.

- [ ] **Step 1: Create `skill-draft/SKILL.md` with exact content**

````markdown
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

## Procedure

Wrap runs four phases in sequence. Phases are independent — failure in phase N does not abort phases N+1 and does not undo phases 1..N-1.

### Phase 0 — Detect scope

Determine which repos the session touched. In order of precedence:

1. **Recall.** Review the conversation and list every path you edited, created, or ran git commands against. This is the primary source of truth.
2. **Dirty-scan cross-check.** For each recalled path (and its parent repos), check whether the working tree is dirty or has unpushed commits. Use whatever dirty-detection tooling is available — if `projdash` MCP tools are present, use them; otherwise run `git status` and `git log @{u}..HEAD` directly.
3. **Confirm with the user.** Present the detected repo list as a single batch via `AskUserQuestion`: *"I'll wrap these repos: [list]. Add or remove any?"*

**Not in scope:** Repos the session only *read*. Reading is not touching.

**Output of Phase 0:** An ordered list of touched-repo roots. Store it in working memory for Phases 1–3.

### Phase 1 — Session-wide memory offload

Cross-cutting things not tied to any one project. Only done once per wrap, before the per-repo loop.

1. Review your conversation context (plus the on-disk transcript at `~/.claude/projects/<slug>/<session-id>.jsonl` if your context has been compacted and you need to recover earlier content).
2. Walk the **cross-project categories** section of `references/categories.md` in order. For each category, ask yourself *"is there anything in this category from this session worth saving?"* and draft candidate items.
3. Each draft item is a concrete: what to save, where to save it, and why.
4. Surface the full set as a single `AskUserQuestion` batch. Let the user approve, edit, or reject the whole set.
5. Execute the approved writes — create or update memory files, modify `MEMORY.md` index entries, etc.

**Checklist-driven:** Walk every category even if you think it is empty. Quiet sessions should not silently skip memory offload.

### Phase 2 — Per-repo loop

For each touched repo in the Phase 0 list, in order, run sub-phases 2a→2b→2c→2d. Finish one repo before starting the next.

Per-repo independence rule: if any sub-phase fails partway through a repo, log the failure, skip remaining sub-phases for *that* repo (especially never push if commit failed), and continue to the next repo. Do not abort the whole wrap.

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

**Wrap's own edits.** Everything wrap wrote during 1, 2a, 2b, 2c (memory updates, CLAUDE.md edits, archived plans, deleted scratch) auto-commits in one commit per repo with this message format:

```
chore: wrap session hygiene

- <one bullet per category of change, e.g. "Archived 2 completed plans">
- <e.g. "Updated CLAUDE.md with 3 new project facts">

Wrap-Session-Id: <current session id if known, else a timestamp>
```

The `Wrap-Session-Id:` trailer lets future tooling distinguish wrap commits from user work.

**User work** (uncommitted changes that existed *before* wrap started). Show `git status` + `git log @{u}..HEAD`. Ask the user per repo:

> `(c)ommit + push / (c)ommit only / (s)tash / (l)eave as-is / (b)ranch-off-and-commit`

Rules for this prompt:

- Never pick an option for the user.
- Never push without the explicit `(c)ommit + push` choice.
- Never force-push. If the push is rejected as non-fast-forward, report "push rejected, commits stay local" and continue.
- `(b)ranch-off-and-commit` creates a new branch from current HEAD, commits there, leaves `main`/the original branch untouched.
- If there is no upstream, `(c)ommit + push` degrades to `(c)ommit only` for that repo; inform the user.

### Phase 3 — Session summary

Always runs, even on cancel or abort. Produce a short natural-language summary covering:

- **Accomplishments per repo:** commits made this session, files touched, plans closed, loose threads captured.
- **Memory offload totals:** how many entries written, to which destinations (grouped by memory type).
- **Rejected or flagged:** anything the agent surfaced that the user declined, and anything explicitly flagged as needing human judgment.
- **Leftovers:** per-repo, what is still dirty, unpushed, or in-progress after the wrap. Naming each explicitly so the user can decide whether to come back to it.

Keep the summary terse — specific numbers, specific paths, specific decisions. No filler.

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
````

- [ ] **Step 2: Verify the file parses as markdown (line count > 100, headers present)**

```bash
wc -l skill-draft/SKILL.md
grep -c '^## ' skill-draft/SKILL.md
```

Expected: line count around 170 ± 20, header count around 8 ± 2.

- [ ] **Step 3: Commit**

```bash
git add skill-draft/SKILL.md
git commit -m "Add wrap SKILL.md main prose"
```

---

## Task 4: Write the Unix SessionEnd reminder hook script

**Files:**
- Create: `hooks/session-end-reminder.sh`

- [ ] **Step 1: Create `hooks/` directory**

```bash
mkdir -p hooks
```

- [ ] **Step 2: Create `hooks/session-end-reminder.sh` with exact content**

```bash
#!/usr/bin/env bash
# wrap skill — SessionEnd reminder hook.
# Prints a one-line nudge if the current cwd has wrap-worthy state.
# Rate-limited to once per 5 minutes via ~/.claude/wrap-nudge-last-fired.
# Must exit 0 always. Never blocks or invokes wrap.

set -u

MARKER="$HOME/.claude/wrap-nudge-last-fired"
RATE_LIMIT_SECONDS=300

# Rate limit: skip if marker is recent
if [ -f "$MARKER" ]; then
    now=$(date +%s)
    last=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt $RATE_LIMIT_SECONDS ]; then
        exit 0
    fi
fi

# Only meaningful if cwd is inside a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0
fi

repo_name=$(basename "$(git rev-parse --show-toplevel)")
signals=()

# 1. Dirty working tree?
dirty_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty_count" -gt 0 ]; then
    signals+=("$dirty_count dirty files")
fi

# 2. Unpushed commits? (only if upstream exists)
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    unpushed_count=$(git log --oneline '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$unpushed_count" -gt 0 ]; then
        signals+=("$unpushed_count unpushed commits")
    fi
fi

# 3. Files in .claude/scripts/?
if [ -d ".claude/scripts" ]; then
    script_count=$(find .claude/scripts -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$script_count" -gt 0 ]; then
        signals+=("$script_count script(s) in .claude/scripts")
    fi
fi

# Print nudge if any signals, update marker
if [ "${#signals[@]}" -gt 0 ]; then
    IFS=', '
    echo "⚠ wrap-worthy state: ${signals[*]} in $repo_name. Consider /wrap next session."
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
fi

exit 0
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x hooks/session-end-reminder.sh
```

- [ ] **Step 4: Smoke-test the script on the wrap repo itself**

```bash
cd ~/skills-dev/wrap
bash hooks/session-end-reminder.sh
```

Expected: If the wrap repo is clean, prints nothing and exits 0. If dirty (e.g. the hook itself is uncommitted), prints a line like `⚠ wrap-worthy state: 1 dirty files in wrap. Consider /wrap next session.`

Verify the marker was written on a non-skipped run:

```bash
ls -l ~/.claude/wrap-nudge-last-fired
```

Expected: file exists with recent mtime.

Delete the marker before proceeding so the next task's tests aren't rate-limited:

```bash
rm -f ~/.claude/wrap-nudge-last-fired
```

- [ ] **Step 5: Commit**

```bash
git add hooks/session-end-reminder.sh
git commit -m "Add Unix SessionEnd reminder hook script"
```

---

## Task 5: Write the Windows PowerShell SessionEnd reminder hook script

**Files:**
- Create: `hooks/session-end-reminder.ps1`

- [ ] **Step 1: Create `hooks/session-end-reminder.ps1` with exact content**

```powershell
# wrap skill — SessionEnd reminder hook (Windows).
# Prints a one-line nudge if the current cwd has wrap-worthy state.
# Rate-limited to once per 5 minutes via ~/.claude/wrap-nudge-last-fired.
# Must exit 0 always. Never blocks or invokes wrap.

$ErrorActionPreference = 'SilentlyContinue'

$Marker = Join-Path $HOME '.claude/wrap-nudge-last-fired'
$RateLimitSeconds = 300

# Rate limit
if (Test-Path $Marker) {
    $last = (Get-Item $Marker).LastWriteTime
    $age = (Get-Date) - $last
    if ($age.TotalSeconds -lt $RateLimitSeconds) {
        exit 0
    }
}

# Must be in a git repo
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { exit 0 }

$repoRoot = git rev-parse --show-toplevel 2>$null
$repoName = Split-Path -Leaf $repoRoot
$signals = @()

# 1. Dirty working tree?
$dirty = git status --porcelain 2>$null
$dirtyCount = if ($dirty) { ($dirty -split "`n" | Where-Object { $_.Trim() }).Count } else { 0 }
if ($dirtyCount -gt 0) {
    $signals += "$dirtyCount dirty files"
}

# 2. Unpushed commits?
git rev-parse --abbrev-ref '@{u}' 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $unpushed = git log --oneline '@{u}..HEAD' 2>$null
    $unpushedCount = if ($unpushed) { ($unpushed -split "`n" | Where-Object { $_.Trim() }).Count } else { 0 }
    if ($unpushedCount -gt 0) {
        $signals += "$unpushedCount unpushed commits"
    }
}

# 3. Files in .claude/scripts/?
if (Test-Path '.claude/scripts') {
    $scripts = Get-ChildItem '.claude/scripts' -File -ErrorAction SilentlyContinue
    $scriptCount = if ($scripts) { $scripts.Count } else { 0 }
    if ($scriptCount -gt 0) {
        $signals += "$scriptCount script(s) in .claude/scripts"
    }
}

# Print and mark
if ($signals.Count -gt 0) {
    $msg = "⚠ wrap-worthy state: " + ($signals -join ', ') + " in $repoName. Consider /wrap next session."
    Write-Host $msg
    $markerDir = Split-Path -Parent $Marker
    if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir | Out-Null }
    New-Item -ItemType File -Path $Marker -Force | Out-Null
}

exit 0
```

- [ ] **Step 2: Smoke-test on the wrap repo**

```bash
cd ~/skills-dev/wrap
pwsh -NoProfile -File hooks/session-end-reminder.ps1 2>&1
```

Expected: same behavior as the bash version — silent on clean, one-line warning on dirty. If `pwsh` isn't available, try `powershell` instead. If neither exists (rare on Windows), note the gap in AUDIT.md and skip this smoke test.

Remove any marker written:

```bash
rm -f ~/.claude/wrap-nudge-last-fired
```

- [ ] **Step 3: Commit**

```bash
git add hooks/session-end-reminder.ps1
git commit -m "Add Windows SessionEnd reminder hook script"
```

---

## Task 6: Write the pressure-scenarios document

**Files:**
- Create: `docs/pressure-scenarios.md`

- [ ] **Step 1: Create `docs/pressure-scenarios.md` with exact content**

```markdown
# Wrap Skill Pressure Scenarios

Manual test scenarios for the wrap skill. Each scenario has a setup, an expected agent behavior, and pass/fail criteria. Transcripts go in `docs/evidence/<scenario-slug>.md` as they are run. `AUDIT.md` rolls them up.

No automated runner — these are manually triggered by running `/wrap` in a session that has been set up per the scenario's setup section.

## Scenarios

### 1. Clean repo, nothing to wrap

**Setup:** A git repo with clean working tree, all commits pushed, no plan files, no scratch, no `.claude/scripts/` files. Start a Claude Code session, edit nothing, run `/wrap`.

**Expected:** Phase 0 detects the repo. Phase 1 walks categories and finds nothing. Phase 2 runs for the one repo, 2a/2b/2c/2d all produce empty findings. Phase 3 prints a "nothing to wrap" summary. No commits made.

**Pass criteria:** Wrap exits cleanly. No files written. No commits. Summary says "nothing to wrap" or equivalent.

**Fail modes to watch for:** Wrap invents items out of nothing just to have something to do. Wrap writes an empty auto-commit in 2d. Wrap aborts on empty input.

### 2. Single repo, dirty tree + unpushed commits

**Setup:** Git repo with 3 modified-but-uncommitted files and 2 commits ahead of upstream. Start a session, run `/wrap`.

**Expected:** Phase 0 picks the repo. Phase 1 handles cross-project offload. Phase 2a walks per-project memory. Phase 2c shows dirty count and unpushed count as findings. Phase 2d prompts the user for the uncommitted work with the 5-option menu.

**Pass criteria:** All four phases exercised, user prompt appears in Phase 2d, Phase 3 summary shows what was committed vs left alone.

### 3. Multi-repo session, 3 repos touched

**Setup:** Start a session that edits files in 3 different git repos. Run `/wrap`.

**Expected:** Phase 0 detects all 3 repos via agent recall, confirms with user. Phase 2 loops 3 times, per-repo independence visible.

**Pass criteria:** All 3 repos appear in Phase 0 confirmation. Each gets its own Phase 2 iteration. Phase 3 summary groups results per repo.

**Fail modes:** Wrap only catches the current `cwd` and misses the others. Wrap treats all 3 repos as one flat list.

### 4. Repo with completed plan file

**Setup:** Git repo with `docs/specs/old-plan.md` whose referenced work is merged and checkboxes all ticked. Run `/wrap`.

**Expected:** Phase 2b classifies the plan as Completed. Loose-thread extraction produces nothing (or minimal). Plan is deleted outright with wrap's auto-commit referencing the deletion.

**Pass criteria:** Plan classification is correct. Deletion happens. Git log shows the deletion in the `chore: wrap session hygiene` commit.

### 5. Repo with abandoned plan file

**Setup:** Git repo with `docs/specs/stalled.md` untouched for 6 weeks, no code changes tying back. Run `/wrap`.

**Expected:** Phase 2b classifies as Abandoned. Archives to `docs/specs/archive/stalled.md` (creates dir if needed) with a frontmatter status note.

**Pass criteria:** File moved, not deleted. Archive dir created. Frontmatter contains `status: abandoned` or equivalent.

### 6. Loose thread in a stale plan (THE CRITICAL SAFETY TEST)

**Setup:** Git repo with `docs/specs/old.md` that is Completed *but contains a line:* "We should fix the retry logic in worker.py — it doesn't back off exponentially." Run `/wrap`.

**Expected:** Phase 2b reads the plan, identifies the loose thread, proposes saving it (e.g., as a new plan `docs/specs/retry-backoff.md`, a memory note, or a GitHub issue). The user approves. The save happens. **Only then** is the old plan deleted.

**Pass criteria:** The loose thread ends up in a durable destination *before* the source is deleted. If the agent deletes the plan without externalizing the thread first, this is a **critical failure** — it violates the core safety rule.

### 7. Merge conflict on wrap's auto-commit

**Setup:** Contrived — stage a conflicting change mid-wrap. Run `/wrap`.

**Expected:** Phase 2d catches the conflict, stashes wrap's edits, leaves user work alone, reports the conflict in Phase 3 summary. Wrap does not abort — it continues to remaining repos if any, and then to Phase 3.

**Pass criteria:** No force-push. No lost data. Phase 3 summary explicitly names the repo where the conflict happened.

### 8. User cancels mid-run during Phase 2 of 3 repos

**Setup:** 3 touched repos. During Phase 2 of repo #2, press `Ctrl+C` or say "stop".

**Expected:** Already-committed work in repo #1 and partial work in repo #2 stays intact. Phase 3 summary shows "completed: repo 1 (all phases); partial: repo 2 (through sub-phase 2a); not reached: repo 3".

**Pass criteria:** No data loss. Summary is accurate about what completed vs what didn't.

### 9. Session touched a non-git-repo directory

**Setup:** Session edits files in a plain directory (no `.git`). Run `/wrap`.

**Expected:** Phase 0 detects the directory, but Phase 2's git operations gracefully skip it. Summary notes "repo X is not a git repo, skipped hygiene."

**Pass criteria:** No errors. No garbage output. The non-git directory is still mentioned in Phase 3.

### 10. projdash present vs absent

**Setup:** Run scenario 2 twice: once on a system with `projdash` MCP tools available, once without.

**Expected:** Same findings produced, same commits, same Phase 3 summary. The internal path differs (`projdash.find_dirty` vs raw `git status`), but the user-visible output is identical.

**Pass criteria:** Equivalent output across both runs. Confirms tool-agnostic prose.

### 11. .claude/scripts/ has one stale scratch + one explicitly-kept script

**Setup:** Git repo with `.claude/scripts/build-once.ps1` (one-off, session-scoped) and `.claude/scripts/keep-me.ps1` whose header comment says `# KEEP: reusable helper for X`. Run `/wrap`.

**Expected:** Phase 2c proposes deleting `build-once.ps1` only. `keep-me.ps1` is left alone because its content marks it as intentional.

**Pass criteria:** Only the one-off is deleted. The intentional script is untouched and no finding is surfaced for it.

### 12. User explicitly said "don't save this" about a discovery

**Setup:** Mid-session, say "don't put that in memory — it was a one-off, not a pattern." Later, run `/wrap`.

**Expected:** Phase 1's category walk does not surface the item. Wrap respects the user's explicit instruction.

**Pass criteria:** The item does not appear in the Phase 1 batch. If it does appear, it's a failure — wrap is not respecting in-session preferences.

## Running a scenario

1. Set up the fixture per the scenario's Setup section.
2. Start a Claude Code session in the fixture's directory (or one that will touch the fixture).
3. Run `/wrap`.
4. Capture the full transcript as `docs/evidence/NN-<slug>.md` with the scenario number as prefix.
5. Judge pass/fail against the pass criteria.
6. Add a row to `AUDIT.md` with the scenario number, status, link to evidence file, and any notes.
```

- [ ] **Step 2: Verify the file**

```bash
wc -l docs/pressure-scenarios.md
grep -c '^### ' docs/pressure-scenarios.md
```

Expected: line count ~180, `### ` header count = 12.

- [ ] **Step 3: Commit**

```bash
git add docs/pressure-scenarios.md
git commit -m "Add 12 pressure scenarios for wrap skill"
```

---

## Task 7: Deploy skill-draft to ~/.claude/skills/wrap

**Files:**
- Create (external): `~/.claude/skills/wrap/SKILL.md`
- Create (external): `~/.claude/skills/wrap/references/*.md`
- Create (external): `~/.claude/skills/wrap/hooks/*` (copied from dev repo)

- [ ] **Step 1: Create the deploy directory**

```bash
mkdir -p ~/.claude/skills/wrap/references ~/.claude/skills/wrap/hooks
```

- [ ] **Step 2: Copy skill-draft contents and hooks**

```bash
cp ~/skills-dev/wrap/skill-draft/SKILL.md ~/.claude/skills/wrap/SKILL.md
cp ~/skills-dev/wrap/skill-draft/references/*.md ~/.claude/skills/wrap/references/
cp ~/skills-dev/wrap/hooks/session-end-reminder.sh ~/.claude/skills/wrap/hooks/
cp ~/skills-dev/wrap/hooks/session-end-reminder.ps1 ~/.claude/skills/wrap/hooks/
chmod +x ~/.claude/skills/wrap/hooks/session-end-reminder.sh
```

- [ ] **Step 3: Verify deployment**

```bash
ls ~/.claude/skills/wrap/
ls ~/.claude/skills/wrap/references/
ls ~/.claude/skills/wrap/hooks/
```

Expected:
- Top level: `SKILL.md`, `references/`, `hooks/`
- `references/`: 5 files (`categories.md`, `finding-schema.md`, `hygiene-checklist.md`, `plan-classification.md`, `session-end-reminder.md`)
- `hooks/`: 2 files (`session-end-reminder.sh`, `session-end-reminder.ps1`)

Also verify that starting a new Claude session in a throwaway directory would list `wrap` in its available skills (manual check — look for it in the next session's skill list).

*(No commit for this step — the deploy target is outside the wrap repo and not a git repo itself.)*

---

## Task 8: Edit project-maintenance to delegate to wrap

**Files:**
- Modify: `~/skills-dev/project-maintenance/skill-draft/SKILL.md`
- Modify: `~/skills-dev/project-maintenance/skill-draft/references/checklist.md`
- Modify: `~/.claude/skills/project-maintenance/SKILL.md` (deploy mirror)
- Modify: `~/.claude/skills/project-maintenance/references/checklist.md` (deploy mirror)

- [ ] **Step 1: Read the current PM SKILL.md to confirm insertion points**

```bash
cat ~/skills-dev/project-maintenance/skill-draft/SKILL.md
```

Confirm the file has this structure (should match):
- Lines 1–4: YAML frontmatter with `name: project-maintenance`
- Line 6: `# Project Maintenance`
- Lines 8–11: one-paragraph description + Interactive/Fleet subagent bullets
- Line 13: `## Operating principles`
- Lines 15–18: numbered principles (Verify before delete, Research before asking, Log everything, Age is a hint)
- Line 20: `## Procedure`
- Line 22: `### 1. Bootstrap`

If the structure differs, adapt the insertion points — the semantic locations (after the opening description, as a new step 0, in operating principles) stay the same even if line numbers drift.

- [ ] **Step 2a: Edit `~/skills-dev/project-maintenance/skill-draft/SKILL.md` — add relationship paragraph**

After the Interactive/Fleet bullets and *before* `## Operating principles`, insert a new paragraph:

```
**Relationship to the `wrap` skill:** For the per-session-hygiene portion of a maintenance pass, this skill delegates to `wrap`. PM's own checklist now covers only the rare/audit-tier items that do not belong in a session-close ritual (default-branch renames, CLAUDE/AGENTS merging, missing README/LICENSE/.gitignore, dead code, large tracked files, disk warnings). If you are running in an interactive session and the user wants a full end-of-session hygiene pass, prefer `/wrap` directly — it does the session-scoped work without PM's audit overhead.
```

Use the Edit tool with these exact strings:

old_string:
```
- **Fleet subagent** — running under `fleet-orchestration`. Produce the same researched findings but return them to the parent as structured data. Do not prompt — the parent drives the approval loop with the user.

## Operating principles
```

new_string:
```
- **Fleet subagent** — running under `fleet-orchestration`. Produce the same researched findings but return them to the parent as structured data. Do not prompt — the parent drives the approval loop with the user.

**Relationship to the `wrap` skill:** For the per-session-hygiene portion of a maintenance pass, this skill delegates to `wrap`. PM's own checklist now covers only the rare/audit-tier items that do not belong in a session-close ritual (default-branch renames, CLAUDE/AGENTS merging, missing README/LICENSE/.gitignore, dead code, large tracked files, disk warnings). If you are running in an interactive session and the user wants a full end-of-session hygiene pass, prefer `/wrap` directly — it does the session-scoped work without PM's audit overhead.

## Operating principles
```

- [ ] **Step 2b: Edit the same file — add "Divergence from wrap" to Operating principles**

Change the first principle to note the divergence:

old_string:
```
1. **Verify before delete.** Never delete untracked files. For tracked files, delete only when (a) the working tree is clean and (b) you can state why the file has served its purpose.
```

new_string:
```
1. **Verify before delete.** Never delete untracked files. For tracked files, delete only when (a) the working tree is clean and (b) you can state why the file has served its purpose. *(Divergence from wrap: the wrap skill **may** delete untracked files with per-item approval. When PM's procedure delegates to wrap as step 0, wrap's looser rule applies during that step — do not let PM's stricter rule override it. PM's stricter rule still applies to everything PM does directly.)*
```

- [ ] **Step 2c: Edit the same file — add step 0 to the Procedure section**

Insert a new `### 0. Delegate to wrap first` step before the existing `### 1. Bootstrap`.

old_string:
```
## Procedure

### 1. Bootstrap
```

new_string:
```
## Procedure

### 0. Delegate to wrap first

Before running any of PM's own checks, invoke the `wrap` skill on this project. Wrap's output (memory offload findings + per-session hygiene findings + action log) is part of this maintenance run. If wrap surfaces findings that overlap with anything in PM's remaining checklist, do not duplicate them — PM's residual checklist covers rare/audit items only.

In fleet-subagent mode, PM's fleet framing propagates through wrap's execution: wrap will produce findings-only output instead of prompting, because the agent running PM is already in that mode.

### 1. Bootstrap
```

- [ ] **Step 3: Edit `~/skills-dev/project-maintenance/skill-draft/references/checklist.md`**

Add a note at the top of the checklist (after the intro paragraph, before the table):

```
**Note:** Rows for per-session hygiene (temp files, uncommitted/unpushed, stale memory, merged branches, stale worktrees) have been moved to the `wrap` skill. PM invokes wrap as step 0 of its procedure, and wrap's findings are part of a PM run. This table now contains only the rare/audit-tier checks PM owns directly.
```

Then remove these rows from the table:
- `Temp files — tracked`
- `Temp files — untracked`
- `Uncommitted / unpushed changes`
- `Stale memory`
- `Merged local branches`
- `Stale worktrees`

Keep all other rows (default branch, TODO/FIXME/XXX, CLAUDE/AGENTS coexistence, missing README/LICENSE/gitignore, dead code, large tracked files, disk warnings).

- [ ] **Step 4: Mirror the same edits to the deploy copies**

```bash
cp ~/skills-dev/project-maintenance/skill-draft/SKILL.md ~/.claude/skills/project-maintenance/SKILL.md
cp ~/skills-dev/project-maintenance/skill-draft/references/checklist.md ~/.claude/skills/project-maintenance/references/checklist.md
```

- [ ] **Step 5: Verify the deploy mirror matches the dev repo**

```bash
diff ~/skills-dev/project-maintenance/skill-draft/SKILL.md ~/.claude/skills/project-maintenance/SKILL.md
diff ~/skills-dev/project-maintenance/skill-draft/references/checklist.md ~/.claude/skills/project-maintenance/references/checklist.md
```

Expected: both diffs empty.

- [ ] **Step 6: Commit the PM edits from within the PM dev repo if it is a git repo**

```bash
if [ -d ~/skills-dev/project-maintenance/.git ]; then
    cd ~/skills-dev/project-maintenance
    git add skill-draft/SKILL.md skill-draft/references/checklist.md
    git commit -m "Delegate per-session hygiene to wrap skill"
    cd ~/skills-dev/wrap
fi
```

If `~/skills-dev/project-maintenance` is not a git repo, note this in `~/skills-dev/wrap/AUDIT.md` under a "dependencies" section and continue.

---

## Task 9: Register the SessionEnd reminder hook via update-config

**Files:**
- Modify (external): `~/.claude/settings.json` (via the `update-config` skill)

- [ ] **Step 1: Invoke the `update-config` skill**

Within the Claude session, invoke:

```
Use the update-config skill to register a SessionEnd hook that runs ~/.claude/skills/wrap/hooks/session-end-reminder.sh on Unix/macOS, or pwsh -NoProfile -File C:/Users/<user>/.claude/skills/wrap/hooks/session-end-reminder.ps1 on Windows. The hook must be non-blocking and run once on session end.
```

The `update-config` skill handles the settings.json editing. Don't hand-edit `settings.json` — that's exactly what `update-config` is for.

- [ ] **Step 2: Verify the hook is registered**

Read `~/.claude/settings.json` and confirm there is a `hooks.SessionEnd` entry referencing `session-end-reminder`.

```bash
grep -A 3 SessionEnd ~/.claude/settings.json
```

Expected: a block containing the hook script path.

- [ ] **Step 3: End a test session and confirm the hook runs**

Start a throwaway session in a git repo with uncommitted changes, exit. The nudge line should appear. Delete the rate-limit marker afterward so subsequent tests are not suppressed:

```bash
rm -f ~/.claude/wrap-nudge-last-fired
```

---

## Task 10: Publish wrap repo to GitHub

**Files:**
- External: GitHub `mtschoen/wrap` (new remote)

- [ ] **Step 1: Create the remote repo via gh CLI**

```bash
cd ~/skills-dev/wrap
gh repo create mtschoen/wrap --public --source=. --description "Claude Code skill for the session-closing ritual: memory offload + repo hygiene" --remote=origin
```

Expected output: repository created, remote added.

- [ ] **Step 2: Push**

```bash
git push -u origin main
```

Expected: commits pushed, upstream tracked.

- [ ] **Step 3: Verify**

```bash
gh repo view mtschoen/wrap --web
```

Optional — just opens the repo page for eyeball check. Or:

```bash
gh repo view mtschoen/wrap | head
```

Confirm the description is correct and the main branch is present.

- [ ] **Step 4: Update `README.md` with the GitHub link and commit**

Read the current README and add this near the top:

```markdown
**Repo:** https://github.com/mtschoen/wrap
```

Commit:

```bash
git add README.md
git commit -m "Add GitHub link to README"
git push
```

---

## Task 11: Run initial pressure scenarios (smoke test: 1, 2, 6)

**Files:**
- Create: `docs/evidence/01-clean-repo.md`
- Create: `docs/evidence/02-dirty-plus-unpushed.md`
- Create: `docs/evidence/06-loose-thread-safety.md`
- Modify: `AUDIT.md`

This is the minimum viable smoke test: one trivial case (1), one common case (2), and the critical safety test (6). Passing all three means the skill is usable. Remaining scenarios come in Task 12.

- [ ] **Step 1: Create `docs/evidence/` directory**

```bash
mkdir -p docs/evidence
```

- [ ] **Step 2: Run Scenario 1 (clean repo, nothing to wrap)**

Create a throwaway git repo:

```bash
mkdir -p /tmp/wrap-test-01
cd /tmp/wrap-test-01
git init -q
echo "# test" > README.md
git add README.md
git commit -q -m "initial"
```

Start a new Claude Code session in `/tmp/wrap-test-01`. Run `/wrap`. Capture the full transcript (agent output + your inputs) and write it to `docs/evidence/01-clean-repo.md` with this shape:

```markdown
# Scenario 1 — Clean repo, nothing to wrap

**Date:** YYYY-MM-DD
**Skill version:** commit <hash>

## Setup
<exactly how the fixture was built>

## Transcript
<paste the session>

## Judgment
- Pass / Fail / Partial
- Notes on what matched and didn't match the pass criteria
```

- [ ] **Step 3: Run Scenario 2 (dirty + unpushed)**

Similarly set up a fixture with dirty tree + unpushed commits, run `/wrap`, capture transcript to `docs/evidence/02-dirty-plus-unpushed.md`.

Fixture setup:

```bash
mkdir -p /tmp/wrap-test-02
cd /tmp/wrap-test-02
git init -q
echo "# test" > README.md
git add README.md
git commit -q -m "initial"
# Simulate upstream by pointing at a bare repo
git init -q --bare /tmp/wrap-test-02-remote
git remote add origin /tmp/wrap-test-02-remote
git push -q -u origin main
# Make unpushed commits
echo "change 1" >> README.md
git commit -aq -m "change 1"
echo "change 2" >> README.md
git commit -aq -m "change 2"
# Dirty the tree
echo "uncommitted" > scratch.txt
echo "more uncommitted" > notes.md
echo "another" > work.log
```

Start a new session in this fixture, run `/wrap`, capture transcript.

- [ ] **Step 4: Run Scenario 6 (loose thread in stale plan — THE critical safety test)**

Fixture:

```bash
mkdir -p /tmp/wrap-test-06/docs/specs
cd /tmp/wrap-test-06
git init -q
echo "# test" > README.md
cat > docs/specs/old.md <<'PLAN'
# Old plan — auth refactor

Status: completed 2026-03-15

- [x] Extract auth module to src/auth/
- [x] Migrate callers
- [x] Tests green

## Notes

We should fix the retry logic in worker.py — it doesn't back off exponentially, and we saw a thundering herd in staging.
PLAN
git add README.md docs/specs/old.md
git commit -q -m "plan and baseline"
# Pretend the referenced work is done
mkdir -p src/auth
echo "# auth module" > src/auth/__init__.py
git add src/auth/__init__.py
git commit -q -m "auth module complete"
```

Start a new session in this fixture, run `/wrap`. Capture transcript.

**The critical assertion:** The agent must identify the "retry logic in worker.py" sentence as a loose thread, propose saving it somewhere durable (memory, new plan file, or issue), get approval, *save it*, and *only then* delete `docs/specs/old.md`. If the plan is deleted without the loose thread being externalized first, this is a hard failure — it violates wrap's core safety rule.

Write the transcript and judgment to `docs/evidence/06-loose-thread-safety.md`.

- [ ] **Step 5: Update AUDIT.md with the three results**

Replace the existing placeholder row with real data:

```markdown
# Wrap Skill Audit Log

Pressure-test results rolled up from `docs/evidence/`. Each scenario from `docs/pressure-scenarios.md` gets a row when it has been run.

| Scenario | Status | Evidence | Notes |
|---|---|---|---|
| 1. Clean repo, nothing to wrap | <Pass/Fail> | [01-clean-repo.md](docs/evidence/01-clean-repo.md) | <brief> |
| 2. Dirty tree + unpushed | <Pass/Fail> | [02-dirty-plus-unpushed.md](docs/evidence/02-dirty-plus-unpushed.md) | <brief> |
| 6. Loose thread safety (CRITICAL) | <Pass/Fail> | [06-loose-thread-safety.md](docs/evidence/06-loose-thread-safety.md) | <brief> |
```

- [ ] **Step 6: Commit**

```bash
cd ~/skills-dev/wrap
git add docs/evidence/ AUDIT.md
git commit -m "Run smoke-test pressure scenarios (1, 2, 6)"
git push
```

- [ ] **Step 7: If any smoke test failed, STOP and fix the skill**

Do not proceed to Task 12 until all three smoke tests pass. If any fail, the fix is to edit `skill-draft/SKILL.md` or the relevant reference file, re-deploy (Task 7 Step 2 again), and re-run the failed scenarios. Document the fix cycle in the evidence file.

Cleanup after each fixture run:

```bash
rm -rf /tmp/wrap-test-01 /tmp/wrap-test-02 /tmp/wrap-test-02-remote /tmp/wrap-test-06
```

---

## Task 12: Run remaining pressure scenarios (3, 4, 5, 7–12)

**Files:**
- Create: `docs/evidence/03-multi-repo.md`
- Create: `docs/evidence/04-completed-plan.md`
- Create: `docs/evidence/05-abandoned-plan.md`
- Create: `docs/evidence/07-merge-conflict.md`
- Create: `docs/evidence/08-user-cancel.md`
- Create: `docs/evidence/09-non-git-directory.md`
- Create: `docs/evidence/10-projdash-present-vs-absent.md`
- Create: `docs/evidence/11-claude-scripts-mixed.md`
- Create: `docs/evidence/12-dont-save-this.md`
- Modify: `AUDIT.md`

- [ ] **Step 1: Run each remaining scenario from `docs/pressure-scenarios.md`**

For each scenario (3, 4, 5, 7, 8, 9, 10, 11, 12):

1. Create the fixture per the scenario's Setup section in `docs/pressure-scenarios.md`. Use `/tmp/wrap-test-NN/` as the convention.
2. Start a new Claude Code session in the fixture root (or one that will touch the fixture).
3. Run `/wrap`.
4. Capture the full transcript.
5. Judge against the pass criteria stated in the scenario.
6. Write the evidence file at `docs/evidence/NN-<slug>.md` with this exact template:

   ```markdown
   # Scenario N — <short title>

   **Date:** YYYY-MM-DD
   **Skill version:** commit <hash>

   ## Setup
   <exactly how the fixture was built>

   ## Transcript
   <paste the session>

   ## Judgment
   - Pass / Fail / Partial
   - Notes on what matched and didn't match the pass criteria
   ```

7. Clean up: `rm -rf /tmp/wrap-test-NN`.

Scenario 10 is special — run it twice, once with projdash MCP available and once without. Both runs go in the same evidence file.

Scenario 7 (merge conflict) is contrived and may require you to artificially stage a conflicting file mid-wrap. Approximate as best possible; note the limitation in the evidence.

- [ ] **Step 2: Update AUDIT.md with all 12 rows**

After running scenarios 3–12, AUDIT.md should have one row per scenario. Replace the previous 3-row table with all 12.

- [ ] **Step 3: If any scenario fails, decide severity**

- **Critical failures** (scenarios 6, 10, plus data-loss failures anywhere): stop and fix the skill. Re-deploy. Re-run. Update evidence.
- **Minor failures** (cosmetic output issues, edge-case handling): record the failure in AUDIT.md's Notes column and move on. File a follow-up as a new plan under `docs/plans/`.

- [ ] **Step 4: Commit + push**

```bash
cd ~/skills-dev/wrap
git add docs/evidence/ AUDIT.md
git commit -m "Run remaining pressure scenarios (3, 4, 5, 7-12)"
git push
```

---

## Task 13: Finalize

- [ ] **Step 1: Update README.md with final status**

Change the Status section in README.md from "Under development" to either "Stable — all pressure scenarios passing" or "Stable with known limitations (see AUDIT.md)" depending on Task 12 outcome.

- [ ] **Step 2: Commit + push**

```bash
cd ~/skills-dev/wrap
git add README.md
git commit -m "Mark wrap skill as stable"
git push
```

- [ ] **Step 3: Final check — is the skill working in a fresh session?**

Start a brand-new Claude Code session in any git repo. Type `/wrap`. The skill should be available, should walk you through its phases, and should behave as specified.

If this smoke check passes: the skill is done.

If it doesn't: debug and iterate. Document the fix cycle in AUDIT.md.
