# `/wrap` skill — design

**Status:** draft, brainstormed 2026-04-11
**Author:** mtschoen + Claude (brainstorming session)
**Repo (dev):** `~/skills-dev/wrap/`
**Deploy target:** `~/.claude/skills/wrap/`
**Publish target:** GitHub `mtschoen/wrap`

## Purpose

`/wrap` is a manually-invoked skill that performs the session-closing ritual for a Claude Code session. It has two equally-mandatory jobs:

1. **Memory offload.** Convert ephemeral working memory — things the model knows from the current conversation but no file/commit captures yet — into durable artifacts (memory entries, CLAUDE.md updates, plan files, commit messages, etc.) before the agent evaporates.
2. **Repo hygiene.** Bring every repo the session touched into a clean "ready for the next agent" state: stale plans removed, scratch cleaned, dirty trees committed or explicitly left, branches pruned, worktrees reconciled. A clean slate means the next session's agent doesn't waste cycles wading through obsolete context.

Both jobs matter. The framing is *"externalize what's about to be destroyed, then leave no mess behind."*

## Non-goals

- **Never auto-runs.** Not triggered by `SessionEnd` hook, not triggered by `Stop` hook, not invoked from other skills programmatically. The user types `/wrap` or it doesn't run. (See *Why intentional-only* below.)
- **Not a repo audit.** Rare-tier checks — default-branch renames, CLAUDE.md/AGENTS.md merges, missing README/LICENSE, dead-code scans, large-file audits, disk warnings — are **not** wrap's job. Those stay in `project-maintenance`.
- **Not stateful.** Wrap does not maintain a durable "last wrap" record. Each invocation asks "what's true right now" and acts accordingly. Idempotent re-runs fall out of this.
- **Not tool-coupled.** Wrap's SKILL.md is written in tool-agnostic prose. It does not name `projdash` MCP functions, CLI tools, or library calls as required. The agent selects the best available tool at runtime.
- **Not cross-session.** If the user starts a new session and runs `/wrap`, wrap only sees what *that* session did. There is no bridge between sessions.

## Why intentional-only

Not every session exit is a wrap. The user distinguishes two cases:

1. **Quick exit** — restarting Claude, shutting down the machine, context-switching. No cleanup wanted. Running wrap here would be wrong (and annoying).
2. **Intentional wrap** — the work on this line of thinking is done. Full per-session hygiene is appropriate.

Wrap is only correct for case 2, and the user is the only entity that knows which case they're in. A `SessionEnd` hook is allowed to *nudge* (see *SessionEnd reminder hook* below) but never to invoke.

## Relationship to `project-maintenance`

`project-maintenance` (hereafter "PM") is the pre-existing repo-hygiene skill. At the time of this spec, PM covers a mix of per-session hygiene (temp files, uncommitted changes, merged branches, stale worktrees, stale memory) and rare-audit hygiene (master→main, CLAUDE/AGENTS merge, README/LICENSE, dead code, large files).

This spec splits PM:

| Check | Moves to `/wrap` | Stays in `project-maintenance` |
|---|---|---|
| Uncommitted / unpushed | ✅ | |
| Temp files — untracked | ✅ | |
| Temp files — tracked | ✅ | |
| Stale memory | ✅ | |
| Merged local branches (prune) | ✅ | |
| Stale worktrees | ✅ | |
| Default branch = `master` | | ✅ |
| TODO/FIXME/XXX audit | | ✅ |
| CLAUDE.md + AGENTS.md merge | | ✅ |
| Missing README/LICENSE/.gitignore | | ✅ |
| Dead code | | ✅ |
| Accidentally tracked large files | | ✅ |
| Disk warnings | | ✅ |

**Dependency arrow:** `project-maintenance → wrap`, never the reverse. Wrap is the portable root; PM is a higher-level audit that delegates per-session-hygiene to wrap.

**How PM delegates (natural language, not programmatic):** PM's procedure gains a new step 0: *"Run the wrap skill on this project first. Its output is part of this maintenance run."* Then PM does its rare-audit checks on top. This is a prose instruction the agent follows, not a function call.

**Consequence for fleet mode:** PM already has a fleet-subagent mode (no prompting, emit findings). When PM in fleet mode runs wrap as step 0, the agent is already in fleet-framing from its parent's dispatch, so it naturally won't prompt while running wrap. Wrap's SKILL.md does not need to mention fleet mode at all — the framing propagates through the agent's conversation context.

**Looser delete semantics:** PM's rule is *"never delete untracked files."* Wrap is allowed to delete untracked files **with explicit per-item approval**, because externalizing scratch and then cleaning it up is wrap's whole purpose. This divergence is documented in both skills' SKILL.md so cross-contamination of assumptions can't happen.

## Scope detection (what counts as "touched")

Wrap always fans out. One `/wrap` invocation wraps every repo the session touched, not just `cwd`.

**Detection, in order of precedence:**

1. **Agent recall** — the model reviews its own conversation context and lists paths it edited, created, or ran git commands against. This is the primary source of truth.
2. **Dirty-scan cross-check** — whatever dirty-detection tooling is available (projdash dirty-scan if present, else `git status` walked across the recalled path set) is used as a safety net to catch repos the model forgot.
3. **User confirmation** — wrap presents the detected set as a single batch and asks the user to add/remove before proceeding.

**Not in scope:** Repos the session only read (no edits, no commits, no git ops). Reading is not touching.

## Phase structure

Wrap runs four phases in sequence. Each phase is independent: a failure in phase N does not undo phases 1..N-1 and does not abort phases N+1..last.

### Phase 0 — Detect scope

- Agent recalls touched paths from conversation.
- Dirty-scan cross-check catches omissions.
- User confirms the repo list via `AskUserQuestion` (single batch).
- Output: ordered list of touched-repo roots.

### Phase 1 — Session-wide memory offload (once per wrap)

Cross-cutting things not tied to any one project. Agent reviews its recall of the conversation (plus the on-disk transcript at `~/.claude/projects/<slug>/<session-id>.jsonl` if context has been compacted) and proposes items in these categories:

| Category | Destination |
|---|---|
| **Learnings about a codebase** | project CLAUDE.md (Phase 2a) *or* project memory |
| **Decisions + rationale** | commit message, plan file, or memory |
| **Unfinished plans** | `docs/superpowers/specs/` / `PLAN.md` / `.plans/` |
| **Open TodoWrite items** | PLAN.md or new plan file |
| **User preferences discovered** | `~/.claude/projects/.../memory/feedback_*.md` |
| **User profile updates** | `~/.claude/projects/.../memory/user_*.md` |
| **Project facts / context** | project memory or CLAUDE.md (Phase 2a) |
| **Gotchas / pitfalls hit** | CLAUDE.md or code comment |
| **Work-in-progress code** | commit-WIP or stash-with-note (Phase 2d) |
| **External references (docs/URLs)** | `~/.claude/projects/.../memory/reference_*.md` |

Session-wide phase handles only cross-project categories (user preferences, user profile, cross-project references, cross-project learnings). Project-specific items defer to Phase 2a.

**Checklist-driven:** the agent walks each category in order, asking itself "is there anything in this category from this session?" and proposing items. This prevents quiet sessions from skipping memory offload entirely.

**Surfacing model:** agent drafts the full set, shows one batch via `AskUserQuestion`, user approves/edits the whole set. Per-item y/n is not used at this layer — too chatty when the set is small.

### Phase 2 — Per-repo loop

For each touched repo in the Phase 0 list, in sequence:

**2a. Per-repo memory offload.** Project-specific facts, project CLAUDE.md/AGENTS.md edits, project-specific memory entries, gotchas discovered this session. Same batch-approve model as Phase 1.

**2b. Plans/specs sweep.**

Look in all the usual spots:
- `docs/superpowers/specs/*.md` (brainstorming skill output)
- `PLAN.md` / `TODO.md` at repo root
- `.plans/` if present
- In-conversation drafts the model can recall

Classify each plan:
- **Completed** — referenced work is merged/pushed, checklist ticked
- **Superseded** — newer plan covers the same ground
- **Abandoned** — no progress for weeks, user has moved on
- **In progress** — active work, uncommitted changes against it
- **Draft / not started** — intentional deferral

**Critical rule — extract loose threads first.** Before *any* plan file is deleted or archived, the agent scans it for "we should fix X later" / "Y might come up again" / unresolved questions, and externalizes those to the appropriate destination (memory, GitHub issue, CLAUDE.md note, new smaller plan file). Only *after* that extraction is complete and approved does the source plan get removed.

Actions after extraction:
- **Completed + tracked in git** → delete outright (git history preserves)
- **Completed + untracked** → ask with bias-to-delete
- **Superseded** → delete, rationale in commit
- **Abandoned** → archive to `docs/superpowers/specs/archive/` (or equivalent) with a note
- **In progress** → keep, optionally update status frontmatter
- **Draft / not started** → keep (intentional deferral)

**2c. Hygiene pass.** The per-session-hygiene slice moved out of PM:

- Uncommitted / unpushed — summary shown, actions deferred to 2d
- Temp files — tracked: check git log; if work landed elsewhere, propose delete
- Temp files — untracked: read contents; propose delete with per-item approval
- Stale memory entries for this project (semantic check: fix-implemented, dangling ref, superseded)
- Merged local branches to prune
- Stale worktrees created this session
- `.claude/scripts/` one-offs — per user's CLAUDE.md rule, delete after use unless explicitly kept

Each finding carries: **what / evidence / recommendation / confidence / action_on_approval**. Findings batch-approved via `AskUserQuestion`.

**2d. Commit + push decision.**

Wrap's own edits from Phases 1–2c (memory updates, CLAUDE.md edits, archived plans, deleted scratch) are auto-committed with a standard message:

```
chore: wrap session hygiene

- <summary of what wrap did in this repo>

Wrap-Session-Id: <session-id>
```

The `Wrap-Session-Id:` trailer makes wrap's commits recognizable in history for any future tooling that wants to distinguish them from user work.

**User work** (uncommitted changes that existed before wrap started) gets a per-repo prompt:

> `(c)ommit + push / (c)ommit only / (s)tash / (l)eave as-is / (b)ranch-off-and-commit`

Wrap never pushes user work without the explicit (c)ommit+push choice, and never force-pushes.

### Phase 3 — Session summary

A short natural-language report shown at the end, covering:

- What was accomplished this session (per repo: commits made, files touched, plans closed, open threads saved)
- What was offloaded to memory (count + destinations)
- Anything wrap rejected or flagged for human judgment
- What's left — e.g., "repo X still has 2 unpushed commits you chose to leave"

Phase 3 always runs, even on abort or cancellation — it's the audit trail.

## Failure modes

**Phase independence.** Failure in phase N leaves phases 1..N-1 intact and proceeds to phase N+1. Phase 3's summary records what completed and what didn't.

**Per-repo independence inside Phase 2.** If repo 2 of 3 fails (merge conflict, push rejected, etc.), wrap logs the failure, skips the rest of repo 2's phases (don't push if commit failed), and continues to repo 3. Both outcomes appear in the final summary.

**Destructive actions are the last thing to fail-forward past.** Within a repo, deletes/rewrites happen *after* memory offload succeeds. If offload fails, nothing gets deleted — loose threads might still be in those files.

**User cancel mid-run.** Whatever has been approved + executed stays done. Wrap prints a "cancelled — completed: X, pending: Z" summary. Already-made auto-commits stay.

**Git operations that fail.**
- Merge conflict on wrap's auto-commit → stash wrap's edits, report, leave user work as-is.
- Push rejected (non-fast-forward) → never force-push. Report "push rejected, commits stay local", move on.
- Upstream missing → treat as "commit only, no push" for that repo.

**Untracked-file deletions.** Only with per-item approval. Each approval logged with full path + explicit yes. Rejections logged with the reason. Never bulk-approved.

**Idempotent re-run.** `/wrap` twice in a row is safe. Second run finds nothing to do in phases that completed the first time, plus any new state that appeared (e.g. new commits between runs). Stateless per-invocation.

## SessionEnd reminder hook

A separate, fully-decoupled nudge mechanism. Registered via `~/.claude/settings.json` as a `SessionEnd` hook. Runs at session exit, prints at most one line, exits 0. Never interactive, never blocks exit, never invokes wrap.

**What it checks** (on the session's final `cwd`, since we don't track touched repos to disk):
1. Working tree dirty? (`git status --porcelain` non-empty)
2. Unpushed commits? (`git log @{u}..HEAD` non-empty, if upstream exists)
3. Any files present in `.claude/scripts/`? (Per the user's CLAUDE.md rule, one-offs should be deleted after use, so presence at exit is itself a signal — no age check needed.)

**Rate limiter.** Marker file at `~/.claude/wrap-nudge-last-fired`. If the hook fired within the last 5 minutes, skip entirely. The marker is updated on every non-skipped run. Wrap itself does not read or write this file — full decoupling.

**Output (example):**

```
⚠ wrap-worthy state: 3 dirty files, 2 unpushed commits in ~/llamalab. Consider /wrap next session.
```

If no signals fire, the hook prints nothing. Silent is valid.

**Scope caveat:** The hook only sees the final `cwd`'s repo. If the session touched multiple repos but exited from a third one, the hook only reports that third repo. This is fine because the hook is a nudge, not a checklist; the user knows what they touched.

**Install:** Skill ships cross-platform hook scripts (`hooks/session-end-reminder.sh` + `hooks/session-end-reminder.ps1`). Skill README points at `update-config` for registering the hook in `~/.claude/settings.json` rather than hand-editing.

## Repo layout

```
~/skills-dev/wrap/
├── README.md                          # overview, install pointer, status
├── AUDIT.md                           # pressure-test findings (grows over time)
├── skill-draft/
│   ├── SKILL.md                       # the skill itself (frontmatter + prose)
│   └── references/
│       ├── categories.md              # memory-offload category checklist (Phase 1 + 2a)
│       ├── plan-classification.md     # plan classifier rules + "extract first" safety
│       ├── hygiene-checklist.md       # Phase 2c items, adapted from PM (wrap-scope only)
│       ├── finding-schema.md          # copied from project-maintenance; divergence OK
│       └── session-end-reminder.md    # nudge-hook spec + settings.json example
├── docs/
│   ├── specs/
│   │   └── 2026-04-11-wrap-design.md  # this document
│   ├── evidence/                      # manual pressure-test transcripts
│   └── pressure-scenarios.md          # list of scenarios to manually test
└── hooks/
    ├── session-end-reminder.sh        # Unix/macOS
    └── session-end-reminder.ps1       # Windows
```

**SKILL.md triggers** (frontmatter description): user typing `/wrap`, "wrap up", "close out the session", "let's finish this session". Explicit intent only — no passive triggers.

**SKILL.md is tool-agnostic prose.** It describes actions ("find repos with uncommitted changes", "look in the usual spots for plan files"), not tool calls. The agent chooses the best available implementation at runtime (projdash MCP tools if present, raw git otherwise).

**`references/finding-schema.md`** is copied from `project-maintenance` at skill-creation time. Drift is acceptable; the two skills serve different purposes and don't need to stay in lockstep.

## Testing strategy

Skills can't be unit-tested like code — the "unit" is the agent following prose instructions. Follow the established pattern from `maintaining-full-coverage`: manual pressure scenarios + evidence transcripts + an `AUDIT.md` that summarizes pass/fail/partial.

**`docs/pressure-scenarios.md`** — working list:

1. Clean repo, nothing to wrap → fast exit with "nothing to do" summary
2. Single repo, dirty tree + unpushed commits → full phase exercise
3. Multi-repo session, 3 repos touched → fan-out works, per-repo independence holds
4. Repo with completed plan file → classified stale, loose threads extracted, deleted
5. Repo with abandoned plan file → classified abandoned, archived not deleted
6. Loose thread in a stale plan ("we should fix bug X later") → captured to memory *before* plan is deleted
7. Merge conflict on wrap's auto-commit → Phase 2d failure path exercised
8. User cancels mid-run during Phase 2 of 3 repos → partial completion report correct
9. Session touched a non-git-repo directory → gracefully skipped
10. projdash present vs absent → correct results via different tool paths
11. `.claude/scripts/` has one stale scratch + one the user explicitly saved → only stale one is offered for deletion
12. User has said "don't save this" about a discovery → wrap respects it, doesn't surface in Phase 1

**Evidence collection:** each scenario run manually, transcript dropped in `docs/evidence/<scenario-slug>.md`. `AUDIT.md` rolls them up into pass/fail/partial counts.

**No automated runner.** Manual only.

## Build sequence (preview — will be expanded by writing-plans)

The implementation plan will cover, roughly in order:

1. Scaffold `~/skills-dev/wrap/` with README, AUDIT.md, skill-draft/, docs/, hooks/
2. Draft `skill-draft/SKILL.md` + all `references/*.md` files
3. Write `hooks/session-end-reminder.sh` and `.ps1`
4. Draft `docs/pressure-scenarios.md`
5. Run a subset of pressure scenarios manually, collect evidence, update AUDIT.md
6. Copy `skill-draft/` to `~/.claude/skills/wrap/` for live use
7. Edit `~/.claude/skills/project-maintenance/SKILL.md` and `references/checklist.md` to delegate to wrap and drop the moved rows
8. Publish `mtschoen/wrap` to GitHub
9. Register the SessionEnd hook via `update-config`
10. Run the remaining pressure scenarios against the deployed skill, finalize AUDIT.md

## Open questions / decisions deferred to implementation

- Exact phrasing of wrap's `AskUserQuestion` batches (how much evidence to show per item before it becomes unreadable)
- Archive-destination naming (`docs/superpowers/specs/archive/` vs `.plans/archive/` vs …) — decide per-project at wrap time based on what already exists
- Whether to add a `--dry-run` flag that runs the detection/research phases without any side effects — punt to v2 unless a pressure scenario shows it's needed

## Summary table

| Decision | Value |
|---|---|
| Trigger | Manual `/wrap` only + decoupled SessionEnd nudge |
| Scope | Always fan out across touched repos |
| Primary purpose | Memory offload (ephemeral → durable) |
| Secondary purpose | Repo hygiene (clean slate for next session) |
| Phases | 0 detect → 1 session-wide offload → 2 per-repo loop → 3 summary |
| Statefulness | Stateless (no durable record) |
| Tool coupling | None — agent picks best available tool at runtime |
| Dependency direction | `project-maintenance → wrap`, never reverse |
| Delete semantics | Tracked+stale: delete; untracked: ask with bias-to-delete |
| Commit behavior | Auto-commit wrap's edits; prompt for user work; never force-push |
| Failure model | Phase + per-repo independence; destructive actions gated on offload success |
| Testing | Manual pressure scenarios + evidence transcripts |
