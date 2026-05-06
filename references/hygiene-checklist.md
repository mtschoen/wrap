# Phase 3c Hygiene Checklist

The per-session-hygiene items that run once per touched repo during Phase 3c. Each item produces zero or more findings; findings follow the shape in `finding-schema.md`.

**Important scope rule:** These items are the *wrap-scope* subset of hygiene. Rare-tier items (master→main, CLAUDE/AGENTS merge, missing README/LICENSE, dead code, large files, disk warnings) are **not** wrap's job — they live in `project-maintenance`. Do not expand this checklist to include them.

## Items

| Check | What to look for | Research required |
|---|---|---|
| Uncommitted changes | `git status --porcelain` non-empty | Categorize files by whether wrap itself made the edit or the user did. Wrap's own edits auto-commit in Phase 3d; user edits get the user prompt. |
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
3. **Log everything.** Every automated action, every user-approved action, and every user-rejected proposal appears in the final summary (Phase 4). Nothing invisible.

## Relationship to PM

Wrap's hygiene checklist is a *subset* of PM's former checklist. Do not duplicate items that have been explicitly moved to PM's rare-tier audit. If a user runs PM, PM runs wrap first, then does its own rare-tier checks on top. The two checklists must not overlap.

## Tooling

Follow tool-agnostic guidance: describe *what* to check in prose. The agent picks the best available implementation — projdash MCP tools if present (e.g. functions that front-load dirty detection and stale-memory scanning), raw git/grep/find otherwise.
