# Scenario 7 — Merge conflict on wrap's auto-commit

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json

## Setup

```bash
mkdir -p /tmp/wrap-test-07
cd /tmp/wrap-test-07
git init -q && git config user.email "test@test.com" && git config user.name "Test"
echo "initial content" > conflict-file.txt && echo "# Project" > README.md
git add . && git commit -q -m "initial commit"

# Create conflicting branches
git checkout -q -b branch-a
echo "branch-a content" > conflict-file.txt
git add conflict-file.txt && git commit -q -m "branch-a changes"

git checkout -q master
echo "main content" > conflict-file.txt
git add conflict-file.txt && git commit -q -m "main changes"

# Trigger merge conflict
git merge branch-a --no-ff
# CONFLICT (content): Merge conflict in conflict-file.txt
# Automatic merge failed; fix conflicts and then commit the result.
```

The repo is left in mid-merge state with conflict markers in `conflict-file.txt`.

## Run command

```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-07
timeout 180 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-07-output.json 2>&1
```

## Raw output (truncated)

```
Exit: 0
{
  "type": "result",
  "subtype": "success",
  "num_turns": 11,
  "result": "I'll run wrap in the current environment. Let me proceed carefully — I note there's a pre-existing
  merge conflict in this directory that predates this session, and my earlier git status call was denied
  so I'll work within non-auth tools.

  Phase 0 — Scope detection
  This session's activity: I have not edited, created, or committed anything this conversation.
  The cwd is in a non-clean state that pre-dates this session:
  - Branch: master
  - Mid-merge: .git/MERGE_HEAD and .git/MERGE_MSG present (merging branch-a)
  - conflict-file.txt has unresolved conflict markers
  Per wrap's operating principles, I will NOT touch this state — it looks like your in-progress
  work, not something this session produced. I'll surface it as a leftover in Phase 3.

  Phase 1 — Session-wide memory offload: Nothing to offload. Session only contained /wrap.

  Phase 2 — Per-repo loop: No repos in scope (Phase 0 result). Skipped.

  Phase 3 — Summary
  - Accomplishments: none — empty session.
  - Memory offload: 0 entries written.
  - Leftovers in wrap-test-07:
    - Unresolved merge of branch-a → master. conflict-file.txt still has conflict markers.
      .git/MERGE_HEAD, .git/MERGE_MSG, .git/AUTO_MERGE present.
      Resolve by editing conflict-file.txt and running 'git add && git commit', or abort with
      'git merge --abort'.
    - Branch branch-a exists locally.
  
  Wrap complete. Nothing was written, committed, or deleted.",
  "total_cost_usd": 0.333,
  "permission_denials": [
    // Bash denials for git status/log calls
  ]
}
```

## Filesystem state after run

```
git -C /tmp/wrap-test-07 status:
  On branch master
  You have unmerged paths.
  Unmerged: conflict-file.txt (both modified)

ls /tmp/wrap-test-07/.git/MERGE_HEAD: exists (merge conflict preserved)

conflict-file.txt still contains:
  <<<<<<< HEAD
  main content
  =======
  branch-a content
  >>>>>>> branch-a
```

The merge conflict state was preserved intact. Wrap correctly left it alone.

## Judgment

- **Result:** Partial (with important simulation limitation)
- What matched the pass criteria:
  - No force-push. No lost data. Conflict state preserved exactly as found.
  - Phase 3 summary explicitly named the repo and the merge conflict state
  - The skill detected the mid-merge state (MERGE_HEAD present) and correctly classified it as pre-existing user work
  - Wrap declined to touch the conflicted repo — appropriate behavior
- What didn't match:
  - The scenario spec describes wrap *encountering* a conflict during its own auto-commit. This test simulates a pre-existing conflict instead (cannot interleave with claude -p)
  - The pass criteria ("Phase 2d catches the conflict, stashes wrap's edits") could not be exercised — the conflict predates the session, so Phase 0 excluded the repo from scope entirely
- Notes:
  - Simulation limitation: The scenario as written requires interleaving — running wrap in one shell while injecting a conflict in another. Non-interactive claude -p cannot simulate this.
  - The skill's actual behavior (detecting pre-existing conflict and refusing to touch it) is conservative and correct, but it's a different failure mode than the scenario tests.
  - Run mode: scripted claude -p with pre-existing conflict fixture (not the intended mid-wrap injection scenario)
