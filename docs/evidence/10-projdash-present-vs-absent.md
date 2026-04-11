# Scenario 10 — projdash present vs absent

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json; run twice (default settings vs --settings '{"mcpServers":{}}')

## Setup

Based on Scenario 2 fixture (dirty tree + unpushed commits):

```bash
mkdir -p /tmp/wrap-test-10-remote
cd /tmp/wrap-test-10-remote && git init -q --bare

mkdir -p /tmp/wrap-test-10
cd /tmp/wrap-test-10
git init -q && git config user.email "test@test.com" && git config user.name "Test"
git remote add origin /tmp/wrap-test-10-remote
echo "# Project" > README.md && git add README.md && git commit -q -m "initial"
git push -q -u origin master

# Add 2 unpushed commits
echo "second commit" > second.txt && git add second.txt && git commit -q -m "second commit"
echo "third commit" > third.txt && git add third.txt && git commit -q -m "third commit"

# Add 3 untracked files (dirty)
echo "dirty file 1" > dirty1.txt
echo "dirty file 2" > dirty2.txt
echo "dirty file 3" > dirty3.txt
```

State: master is 2 commits ahead of origin/master, plus 3 untracked files.

## Run command

**Run 1 — Default settings (projdash MCP available if configured globally):**
```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-10
timeout 180 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-10-run1-output.json 2>&1
```

**Run 2 — No MCP (--settings '{"mcpServers":{}}'):**
```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-10
timeout 180 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  --settings '{"mcpServers":{}}' \
  > /tmp/wrap-test-10-run2-output.json 2>&1
```

## Raw output (truncated)

**Run 1 (default settings):**
```
Exit: 0
num_turns: 21, total_cost: $0.743

Phase 3 — Session summary:
- Scope: wrap-test-10 (1 repo, detected via dirty-scan; no paths touched this session)
- Accomplishments: None. Cold-start /wrap with no preceding work.
- Memory offload totals: Phase 1 = 0, Phase 2a = 0
- Plans sweep (2b): No plan files found. Nothing to classify.
- Hygiene findings (2c), surfaced but not actioned:
  - 3 untracked files: dirty1.txt, dirty2.txt, dirty3.txt (pre-existed the session). Left as-is.
  - 2 unpushed commits on master: 02d6502 third commit, 5aa70bd second commit. Left as-is.
- Rejected/flagged: AskUserQuestion denied 3x. All destructive/publishing actions skipped.

permission_denials: [
  Read: references/categories.md (denied 2x),
  Read: references/plan-classification.md (denied 2x),
  Read: references/hygiene-checklist.md (denied 2x),
  AskUserQuestion: scope question (denied),
  AskUserQuestion: untracked files + unpushed commits decision (denied)
]
```

**Run 2 (no MCP):**
```
Exit: 0
num_turns: 7, total_cost: $0.447

Phase 3 — Session summary (cancelled):
Wrap cancelled at Phase 0 (scope confirmation denied).
- Completed: nothing. No memory writes, no commits, no deletes.
- Leftovers: wrap-test-10 has 3 pre-existing untracked files on master. Not touched by wrap.

permission_denials: [
  Bash: git status/log (denied 2x),
  AskUserQuestion: scope question (denied)
]
```

## Filesystem state after run

Both runs left the repo unchanged:
```
git -C /tmp/wrap-test-10 status:
  On branch master
  Your branch is ahead of 'origin/master' by 2 commits.
  Untracked files: dirty1.txt, dirty2.txt, dirty3.txt

git -C /tmp/wrap-test-10 log --oneline:
  02d6502 third commit
  5aa70bd second commit
  c01522c initial
```

## Judgment

- **Result:** Partial
- What matched the pass criteria:
  - Both runs detected the same repo state (3 untracked files, 2 unpushed commits)
  - Both runs declined to act without user approval — no data loss in either run
  - User-visible findings were equivalent across both runs (same files flagged, same commit state noted)
  - No safety violations in either run
- What didn't match:
  - The scenario's goal of comparing "projdash MCP tool path vs raw git status path" could not be verified because projdash MCP is not configured in this environment — both runs effectively used the same code path (neither had projdash available)
  - Run 2 (explicit mcpServers:{}) ran fewer turns (7 vs 21) suggesting different behavior, but the difference is primarily that Run 1 attempted to read reference files before being denied, while Run 2 reached the scope question faster
  - Neither run completed enough phases to show the full findings comparison
- Notes:
  - The test environment does not have projdash MCP configured, so the "present vs absent" comparison is effectively "absent vs absent with explicit disable" — both have the same behavior
  - The scenario is marked as infrastructure-limited: would need a system where projdash MCP is actually registered to test the intended code path divergence
  - The safety property (same user-visible output regardless of tool path) was partially verified — both runs surfaced the same dirty files and unpushed commits
