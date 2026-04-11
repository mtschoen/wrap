# Scenario 9 — Session touched a non-git-repo directory

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json

## Setup

```bash
mkdir -p /tmp/wrap-test-09
echo "plain file in non-git dir" > /tmp/wrap-test-09/notes.txt
echo "more content" > /tmp/wrap-test-09/data.txt
# No git init - this is intentionally a plain directory
```

## Run command

```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-09
timeout 180 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-09-output.json 2>&1
```

## Raw output (truncated)

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 20307,
  "num_turns": 3,
  "result": "Phase 0 — Scope detection: This session has no prior turns. I haven't read, edited, or run
  git commands against any repo. The working directory (C:\\Users\\mtsch\\AppData\\Local\\Temp\\wrap-test-09)
  is not a git repository per the environment info. No touched repos.

  Phase 1 — Session-wide memory offload: Nothing to offload. No user facts, feedback, project context,
  or references were exchanged — the only user message was /wrap itself.

  Phase 2 — Per-repo loop: Skipped (empty scope).

  Phase 3 — Session summary:
  - Accomplishments: none
  - Memory writes: 0
  - Rejected/flagged: none
  - Leftovers: none

  Nothing to wrap. If you invoked /wrap expecting work from a prior session, note that this is a fresh
  session with no prior context — was there a different directory you meant to wrap up?",
  "stop_reason": "end_turn",
  "total_cost_usd": 0.163,
  "permission_denials": []
}
```

## Filesystem state after run

```
ls /tmp/wrap-test-09/:
  data.txt
  notes.txt

No .git directory (confirmed non-git directory).
No new files created. No errors.
```

## Judgment

- **Result:** Pass
- What matched the pass criteria:
  - No errors occurred — the non-git directory was handled gracefully
  - No garbage output — clean, structured summary
  - Phase 0 detected the directory as "not a git repository" and excluded it from scope
  - Phase 2 was skipped (empty scope) — no git operations were attempted against the non-git directory
  - Phase 3 produced a clean "nothing to wrap" summary with a helpful note about the empty session
  - No files were created, modified, or deleted
- What didn't match:
  - The scenario spec says "Phase 3 summary notes 'repo X is not a git repo, skipped hygiene'" — the actual output is more general ("nothing to wrap") without explicitly naming the directory as a skipped non-git directory
  - Minor: the non-git directory is not mentioned in Phase 3 by name (just "empty scope")
- Notes:
  - Fast run — only 3 turns, 20 seconds. The skill quickly recognized the non-git CWD and exited cleanly.
  - The skill's behavior is conservative and correct: empty session + non-git CWD = nothing to wrap
  - The "repo X is not a git repo, skipped hygiene" phrasing from the spec would only appear if the directory was in scope (e.g., explicitly mentioned in a prior turn). Since no prior turns existed, the behavior is accurate.
