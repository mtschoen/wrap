# wrap

A Claude Code skill that runs the session-closing ritual: externalizes ephemeral working memory into durable artifacts, then brings every touched repo into a clean state for the next session.

See `docs/specs/2026-04-11-wrap-design.md` for the full design rationale.

**Repo:** https://github.com/mtschoen/wrap

## Status

Stable with known testing limitations — all 12 pressure scenarios executed, 5 pass + 7 partial (partials are testing-infrastructure limits, not skill defects). No safety violations in any run. See `AUDIT.md` for full results.

## Install

1. Copy `skill-draft/` contents to `~/.claude/skills/wrap/`.
2. Register the `SessionEnd` hook in `~/.claude/settings.json` — use the `update-config` skill, pointing it at `hooks/session-end-reminder.sh` (Unix/macOS) or `hooks/session-end-reminder.ps1` (Windows).

## Invocation

Type `/wrap` at the end of a session when you are ready to close out. Wrap is always intentional — it never auto-runs.
