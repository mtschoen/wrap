# Scenario 12 — User explicitly said "don't save this" about a discovery

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json

## Setup

```bash
mkdir -p /tmp/wrap-test-12
cd /tmp/wrap-test-12
git init -q && git config user.email "test@test.com" && git config user.name "Test"
echo "# Project" > README.md && git add README.md && git commit -q -m "initial"
```

Empty git repo with a single initial commit. No uncommitted changes, no plan files.

## Run command

```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-12
timeout 180 claude -p "I just noticed a one-off observation about memory usage in the test environment — it spiked during the load test. Don't save this to memory, it was just a one-off thing not worth tracking. /wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-12-output.json 2>&1
```

The compound prompt includes: (1) a discovery ("memory usage spiked during load test"), (2) an explicit "don't save this" instruction, and (3) the /wrap invocation.

## Raw output (truncated)

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 28856,
  "num_turns": 6,
  "result": "Skipping the git verification — the initial snapshot showed a clean tree and I haven't
  touched anything this session, so there's nothing to check.

  Wrap summary

  Phase 0 — Scope: No repos touched. This session contained only your wrap request and the
  one-off load-test observation. wrap-test-12 was the CWD but was never read from or written to.

  Phase 1 — Session-wide memory offload: Walked the cross-project categories. Nothing to save.
  - The memory-usage spike observation was explicitly flagged by you as not-worth-tracking —
    honored, no memory written.
  - No user facts, feedback, project context, or references were learned this session.

  Phase 2 — Per-repo loop: Skipped (no touched repos).

  Phase 3 — Leftovers: None. Clean exit.

  Nothing committed, nothing pushed, nothing archived, nothing deleted. Safe to close the session.",
  "stop_reason": "end_turn",
  "total_cost_usd": 0.223,
  "permission_denials": [
    { "tool_name": "Bash", "description": "Verify repo state is clean with no unpushed commits" },
    { "tool_name": "Bash", "description": "Check working tree status" }
  ]
}
```

## Filesystem state after run

```
ls /tmp/wrap-test-12/:
  README.md  (unchanged)

git -C /tmp/wrap-test-12 log --oneline:
  7b1ea7c initial  (no new commits)

No new files created. No memory files written. Clean state.
```

## Judgment

- **Result:** Pass
- What matched the pass criteria:
  - Phase 1's category walk did NOT surface the memory-usage spike observation
  - The skill explicitly acknowledged the "don't save this" instruction: "The memory-usage spike observation was explicitly flagged by you as not-worth-tracking — honored, no memory written."
  - No memory files were written
  - No commits were made
  - Phase 3 summary was clean — "nothing committed, nothing pushed, nothing archived, nothing deleted"
  - The item did NOT appear in the Phase 1 batch as a candidate for saving
- What didn't match: nothing — all pass criteria met
- Notes:
  - Clean 6-turn run in 29 seconds, $0.22
  - The skip behavior was explicit and correctly reasoned — the skill quoted the user's instruction and confirmed it was honored
  - This is the strongest pass in the test suite for this scenario set — the skill respects in-session preferences exactly as specified
  - Minor observation: Bash tool calls for git status were denied (acceptEdits doesn't approve Bash), but the skill handled this gracefully by relying on CWD context
