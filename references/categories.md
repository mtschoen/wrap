# Memory Offload Categories

The checklist the agent walks during Phase 2 (session-wide offload) and Phase 3a (per-repo offload). For each category, the agent asks itself *"is there anything in this category from this session?"* and proposes items if so.

## Cross-project categories (Phase 2 only)

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

## Per-project categories (Phase 3a only)

These run once per touched repo inside Phase 3's loop.

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

- **Destination:** commit as WIP or stash with a descriptive note. Decided in Phase 3d (commit decision).
