# Scenario 5 — Repo with abandoned plan file

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json

## Setup

```bash
mkdir -p /tmp/wrap-test-05/docs/specs
cd /tmp/wrap-test-05
git init -q && git config user.email "test@test.com" && git config user.name "Test"
echo "# Project" > README.md && git add README.md && git commit -q -m "initial"

cat > docs/specs/stalled.md << 'EOF'
# Plan: Refactor database layer

**Created:** 2025-02-15
**Last updated:** 2025-02-20

## Status: In Progress

## Tasks
- [x] Analyze current DB layer
- [ ] Write migration scripts
- [ ] Update integration tests
- [ ] Deploy

## Notes
This was started but the team pivoted. Nobody has touched this in weeks.
EOF

# Commit with a past date to simulate staleness
GIT_AUTHOR_DATE="2025-02-20T10:00:00" GIT_COMMITTER_DATE="2025-02-20T10:00:00" \
  git add docs/specs/stalled.md && git commit -q -m "add stalled plan"
```

## Run command

```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-05
timeout 180 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-05-output.json 2>&1
```

## Raw output (truncated)

```
Exit: 0
{
  "type": "result",
  "subtype": "success",
  "num_turns": 19,
  "result": "The AskUserQuestion was cancelled/denied — treating this as user cancel. Per wrap's cancel
  handling, I stop here without executing destructive actions and produce the Phase 3 summary.

  Phase 3 — Session summary
  - Scope detected: wrap-test-05 (clean, no upstream, branch master, 2 commits)
  - Session was empty: no prior edits, no conversation content.
  - Plans sweep finding (not executed):
    - docs/specs/stalled.md — tracked, last updated 2025-02-20, explicitly abandoned ('team pivoted').
      Classified as abandoned. No loose threads to extract. Recommended action was delete; no action
      taken because approval was not granted.
  - Hygiene (Phase 2c): not run — gated on 2a/2b completion + approval.
  - Commits (Phase 2d): none. Working tree was and remains clean.
  - Leftovers: wrap-test-05 — clean tree, but docs/specs/stalled.md is still in-tree and still stale.",
  "total_cost_usd": 0.649,
  "permission_denials": [
    // Bash denials for git status/log,
    // Read denials for references/plan-classification.md, references/categories.md,
    //   references/hygiene-checklist.md,
    // AskUserQuestion with:
    {
      "question": "Is wrap-test-05 the only repo in scope for this wrap?",
      // + "docs/specs/stalled.md is a tracked plan, ~14 months idle, explicitly marked abandoned..."
      //   "What should wrap do with it? [Delete it / Archive it / Leave it alone]"
    }
  ]
}
```

Key observation: The skill classified the plan as "abandoned" (~14 months idle, explicit "team pivoted" note), found no loose threads, and proposed deletion (not archival). Per pass criteria, archival to `docs/specs/archive/` was the expected action. Wrap's recommendation was "delete" rather than "archive."

## Filesystem state after run

```
find /tmp/wrap-test-05 -name "*.md":
  /tmp/wrap-test-05/docs/specs/stalled.md  (unchanged — AskUserQuestion was denied)
  /tmp/wrap-test-05/README.md

git -C /tmp/wrap-test-05 log --oneline:
  2984876 add stalled plan
  740697a initial
```

No archive directory was created. File remains in place.

## Judgment

- **Result:** Partial
- What matched the pass criteria:
  - Phase 2b detected and classified the plan as abandoned (idle ~14 months, explicit "team pivoted" note)
  - No loose threads were found (unchecked tasks but no freeform observations to extract)
  - No destructive action taken without user approval
  - Phase 3 summary clearly named the leftover and its recommended action
- What didn't match:
  - The skill proposed "delete" rather than "archive to docs/specs/archive/stalled.md" — the pass criteria specifies archival for abandoned plans, not outright deletion
  - The archive dir was not created; the frontmatter `status: abandoned` addition was not proposed
  - AskUserQuestion was denied so no actual action was taken; full path could not be verified
- Notes:
  - Minor failure: the plan-classification reference may specify "delete" for abandoned plans rather than archive. The scenario pass criteria says "archive" but the skill chose "delete." This is a potential mismatch between the scenario spec and the skill's reference file — worth investigating `references/plan-classification.md`.
  - 19 turns with multiple retried tool calls attempting to read reference files and git status before giving up
