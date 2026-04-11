# Scenario 11 — .claude/scripts/ has one stale scratch + one explicitly-kept script

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json

## Setup

```bash
mkdir -p /tmp/wrap-test-11/.claude/scripts
cd /tmp/wrap-test-11
git init -q && git config user.email "test@test.com" && git config user.name "Test"
echo "# Project" > README.md && git add README.md && git commit -q -m "initial"

# One-off script (no KEEP marker)
cat > .claude/scripts/build-once.ps1 << 'EOF'
# Temporary build script
Write-Host "Building..."
dotnet build
EOF

# Intentionally-kept script with KEEP marker
cat > .claude/scripts/keep-me.ps1 << 'EOF'
# KEEP: reusable helper for X
# This script sets up the test environment for all runs
function Setup-TestEnv {
    Write-Host "Setting up test environment"
}
EOF

git add . && git commit -q -m "add scripts"
```

## Run command

```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-11
timeout 180 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-11-output.json 2>&1
```

## Raw output (truncated)

```
Exit: 0
{
  "type": "result",
  "subtype": "success",
  "num_turns": 16,
  "result": "I'll ask in plain text instead.

  This session has no prior conversation — no files edited, no commits made by me.
  The current working directory wrap-test-11 is the only repo in scope, and it's clean.
  Phases 1, 2a, 2b all have nothing to offload.

  Phase 2c hygiene — one finding:
  - .claude/scripts/build-once.ps1 — header says '# Temporary build script'. Your global convention:
    'Delete one-off scripts after use unless asked to keep them.' This is a tracked file (committed
    in 47a5cc1), so deleting creates a new commit.
  - .claude/scripts/keep-me.ps1 — explicitly marked # KEEP, leave alone.

  Decision needed: delete build-once.ps1 (creates wrap auto-commit) or keep it?

  No upstream is configured on master, so no pushing regardless. There's no user work to commit
  in Phase 2d.",
  "total_cost_usd": 0.590,
  "permission_denials": [
    // Bash denials for git status/log,
    // AskUserQuestion asking:
    // - Scope: confirm wrap-test-11 only (options: Yes / Add another repo / Skip)
    // - Phase 2c: delete build-once.ps1 (options: Delete it / Keep it)
  ]
}
```

Key behavior: The skill correctly distinguished between:
- `build-once.ps1`: "# Temporary build script" header → flagged for deletion
- `keep-me.ps1`: "# KEEP: reusable helper for X" → explicitly left alone, no finding surfaced

## Filesystem state after run

```
ls /tmp/wrap-test-11/.claude/scripts/:
  build-once.ps1  (unchanged — AskUserQuestion was denied)
  keep-me.ps1     (unchanged — explicitly kept, no finding)

git -C /tmp/wrap-test-11 log --oneline:
  47a5cc1 add scripts
  a869d38 initial
```

No deletion happened because AskUserQuestion was denied. Both scripts remain in place.

## Judgment

- **Result:** Pass (detection and classification correct; execution blocked by non-interactive run mode)
- What matched the pass criteria:
  - `build-once.ps1` was correctly identified as a one-off script for deletion (header: "# Temporary build script")
  - `keep-me.ps1` was correctly left alone — the # KEEP marker was respected, no finding surfaced for it
  - Only one finding was produced in Phase 2c (for the one-off script only)
  - The AskUserQuestion correctly proposed only deleting `build-once.ps1`, not `keep-me.ps1`
  - The distinction between the two scripts was made correctly based solely on file content
- What didn't match:
  - Actual deletion did not execute (AskUserQuestion denied in non-interactive mode)
  - Git log does not show the deletion wrap-commit; can only verify detection, not execution
- Notes:
  - The KEEP marker detection worked exactly as specified — the skill read the file content and respected the marker
  - 16 turns with Bash and AskUserQuestion denials, but the core classification logic worked correctly
  - This is a clean partial-pass: detection = Pass, execution = blocked by test mode
