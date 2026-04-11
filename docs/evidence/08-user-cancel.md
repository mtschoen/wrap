# Scenario 8 — User cancels mid-run during Phase 2

**Date:** 2026-04-11
**Skill version:** commit 70c531f
**Run mode:** claude -p, --permission-mode acceptEdits, --output-format json; timeout 30s (simulated cancel via timeout)

## Setup

```bash
mkdir -p /tmp/wrap-test-08-a /tmp/wrap-test-08-b /tmp/wrap-test-08-c

for repo in a b c; do
  cd /tmp/wrap-test-08-$repo
  git init -q && git config user.email "test@test.com" && git config user.name "Test"
  echo "# Repo $repo" > README.md && git add README.md && git commit -q -m "initial"
  echo "change" >> README.md
done
```

## Run command

Two runs were attempted:

**Run 1 (simulated cancel via timeout 30s):**
```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-08-a
timeout 30 claude -p "/wrap" \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  --add-dir /tmp/wrap-test-08-a \
  --add-dir /tmp/wrap-test-08-b \
  --add-dir /tmp/wrap-test-08-c \
  > /tmp/wrap-test-08-output.json 2>&1
echo "Exit: $?"
```
**Exit code: 124** (timeout). Output file was empty (0 bytes) — the session had not yet produced any JSON output when killed.

**Run 2 (natural run with AskUserQuestion denied, simulating user abort):**
```bash
SESSION_ID=$(python -c "import uuid; print(uuid.uuid4())")
cd /tmp/wrap-test-08-a
timeout 120 claude -p "I've been working in 3 repos this session. Please start /wrap but I'll stop you mid-way." \
  --session-id "$SESSION_ID" \
  --permission-mode acceptEdits \
  --output-format json \
  > /tmp/wrap-test-08-output.json 2>&1
```

## Raw output (truncated)

**Run 1:** Empty output (timeout before first JSON token).

**Run 2:**
```
Exit: 0
{
  "type": "result",
  "subtype": "success",
  "num_turns": 5,
  "result": "",
  "total_cost_usd": 0.344,
  "permission_denials": [
    {
      "tool_name": "AskUserQuestion",
      "question": "Which 3 repos did you work in this session? Please list their paths.",
      "options": ["I'll list them", "Use current directory only"]
    }
  ]
}
```

The session ended when the AskUserQuestion (asking for repo list) was denied. The skill treated the denial as a cancel signal and stopped cleanly.

## Filesystem state after run

```
# All 3 repos unchanged:
git -C /tmp/wrap-test-08-a log --oneline: initial
git -C /tmp/wrap-test-08-b log --oneline: initial
git -C /tmp/wrap-test-08-c log --oneline: initial

# All repos still have dirty README.md (unstaged change)
# No wrap commits made in any repo
```

## Judgment

- **Result:** Partial
- What matched the pass criteria:
  - No data loss — all 3 repos remained intact with their pre-wrap state preserved
  - When AskUserQuestion was denied (simulating user cancel), the skill stopped cleanly without any destructive actions
  - Already-started work (in this case, nothing had been committed yet) was left intact
- What didn't match:
  - Scenario spec requires cancel "mid-run during Phase 2 of repo #2" — this requires interactive control to cancel at a specific sub-phase
  - Phase 3 summary showing "completed: repo 1 (all phases); partial: repo 2 (through sub-phase 2a); not reached: repo 3" was not produced because the session ended before Phase 2 began
  - The timeout approach (timeout 30) produced no output at all (JSON format buffers until completion)
- Notes:
  - Simulation limitation: True mid-run cancel during Phase 2 requires interactive session control. Non-interactive claude -p can only simulate "user denied a question" or "SIGTERM via timeout."
  - The timeout approach is not effective with --output-format json because the JSON is written only at session end
  - Using AskUserQuestion denial as the cancel proxy does test the safety property: skill stops cleanly and doesn't act destructively
  - Run mode: simulated cancel via AskUserQuestion denial (not the intended mid-Phase 2 Ctrl+C scenario)
