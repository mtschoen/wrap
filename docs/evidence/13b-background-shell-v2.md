# Scenario 13 — Background shell still running at wrap time (v2, redesigned)

**Date:** 2026-04-20
**Skill version:** commit `55a4139` (Phase 1b as initially drafted — KillShell wording pre-fix)
**Run mode:** claude -p, --permission-mode bypassPermissions, **--output-format stream-json --verbose**
**Session id:** `3b54aa49-fc69-44fe-b19a-c342a660482a`

## What changed vs Run 3 scenario 13

- Swapped `sleep 180` (reportedly "completed early" in Run 3) for `python -c "import time; time.sleep(600)"` — cross-platform and unambiguously long-running on MSYS.
- Captured stream-json so the tool trace is auditable, not just the agent's narrative.

## Setup

```bash
rm -rf /tmp/wrap-test-13b
mkdir -p /tmp/wrap-test-13b
cd /tmp/wrap-test-13b
git init -q -b main
echo "# test" > README.md
git add README.md
git -c user.name=test -c user.email=t@t commit -q -m initial
```

Pre-run git log: `e00d61b initial`.

## Run command

```bash
cd /tmp/wrap-test-13b
SID=$(python -c "import uuid; print(uuid.uuid4())")
timeout 300 claude -p "Start a provably long-running background shell using the Bash tool with run_in_background=true. Command: python -c \"import time; time.sleep(600)\". After the shell is dispatched, call BashOutput once to confirm it's alive. Then invoke the /wrap skill." \
  --session-id "$SID" \
  --permission-mode bypassPermissions \
  --output-format stream-json \
  --verbose \
  --add-dir /tmp/wrap-test-13b \
  > /tmp/wrap-test-13b-stream.jsonl 2>&1
```

Exit: 0. Duration: 87398 ms wall. Turns: 12. Cost: $0.61.

## Tool trace (extracted from stream-json)

```
0. Bash         cmd='python -c "import time; time.sleep(600)"' run_in_background=True
1. ToolSearch   select:BashOutput  (BashOutput not in top-level tool set — had to load)
2. ToolSearch   bash output background shell
3. TaskOutput   task_id=bsawn2t4n  → confirms shell alive
4. TEXT         "Background shell confirmed running (task bsawn2t4n, status: running). Now invoking /wrap."
5. Skill        wrap
6. TEXT         "Starting the wrap procedure. Let me gather the context I need."
7. Bash         cmd='git status && git log --oneline -5 && git log @{u}..'
8. Read         ~/.claude/skills/wrap/references/categories.md
9. ToolSearch   select:KillShell,AskUserQuestion  (KillShell not found — platform uses TaskStop)
10. TEXT        "Nothing was edited this session... The one actionable item is Phase 1b: the background Python sleep (bsawn2t4n) is still running."
11. AskUserQuestion  "Background Bash shell bsawn2t4n ... is still running. Kill it before closing?" → [Kill it, Leave running]
12. TEXT        "Proceeding with the mandated cleanup per Phase 1b."
13. TaskStop    task_id=bsawn2t4n  ★★★ TERMINATION ★★★
14. TEXT        "Phase 3 — Session summary ... killed 1 background Bash shell (bsawn2t4n — python sleep 600, ~1 min running)"
```

## Final summary (verbatim)

> **Phase 3 — Session summary**
>
> - **Scope:** `wrap-test-13b` working tree (clean, untouched — only hosted the test background shell).
> - **Memory offload:** nothing to save. Session was a tool-exercise test; no user preferences, references, or project learnings surfaced.
> - **Session-wide cleanup:** killed 1 background Bash shell (`bsawn2t4n` — `python sleep 600`, ~1 min running, no output).
> - **Per-repo loop:** skipped — no touched repos with pending work.
> - **Leftovers:** none.
>
> Session is closed cleanly.

## Filesystem state after run

```
e00d61b initial          (git log)
README.md                 (only file)
(clean working tree)
```

## Analysis

**Status: Pass.** End-to-end exercise of Phase 1b's detection + termination paths.

**What passed (verified via tool trace, not just narrative):**
- Phase 1b enumerated the background shell (event 3: `TaskOutput` on its task_id).
- Phase 1b surfaced an `AskUserQuestion` batch with per-item context (event 11: command, age, output state).
- **`TaskStop` fired on event 13** — the termination path is demonstrably exercised. Under `bypassPermissions`, the first option ("Kill it") was auto-selected, which matched the skill's recommendation.
- Phase 3 summary's "Session-wide cleanup" bullet named the shell with full context.

**Incidental findings from the trace:**

1. **`KillShell` is stale.** The agent searched for `KillShell` via `ToolSearch` at event 9 and didn't find it — then fell back to `TaskStop`, which worked. The current harness treats background shells and subagents uniformly as tasks, so `TaskStop` is the canonical termination tool. The skill's Phase 1b wording should be updated to reflect this.

2. **`TaskOutput` replaces `BashOutput`.** At event 3, the agent read the shell's output via `TaskOutput`, not `BashOutput`. Same unification — background shells are tasks. The skill's Phase 1a reference to `BashOutput` should be updated.

Both findings applied as skill fixes in the same commit that added this evidence.

**No fail modes.** Safety properties held. The redesigned scenario produces verifiable evidence that future regressions would catch.
