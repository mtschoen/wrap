# Scenario 14 — Subagent output contains loose thread (v2, redesigned)

**Date:** 2026-04-20
**Skill version:** commit `55a4139` (Phase 1b as initially drafted — "still running" wording pre-fix)
**Run mode:** claude -p, --permission-mode bypassPermissions, **--output-format stream-json --verbose**
**Session id:** `777cc11e-b67f-4e3f-b6d2-d1e6eb013621`

## What changed vs Run 3 scenario 14

- Replaced the prompt-injected "worker.py retry" follow-up with a real source file (`src/fetcher.py` containing a hardcoded `DEFAULT_TIMEOUT = 30`).
- Subagent task rewritten to produce *organic* analysis: "Write a short analysis of the timeout handling. Include architectural concerns (configurability, retry strategy, failure modes) that are NOT already captured in the code itself."
- Captured stream-json so the inspect-vs-skip decision is auditable.

## Setup

```bash
rm -rf /tmp/wrap-test-14b
mkdir -p /tmp/wrap-test-14b/src
cat > /tmp/wrap-test-14b/src/fetcher.py <<'EOF'
import requests

DEFAULT_TIMEOUT = 30

def fetch(url):
    return requests.get(url, timeout=DEFAULT_TIMEOUT)
EOF
cd /tmp/wrap-test-14b
git init -q -b main
git add src/fetcher.py
git -c user.name=test -c user.email=t@t commit -q -m initial
```

Pre-run git log: `167fca6 initial`.

## Run command

```bash
cd /tmp/wrap-test-14b
SID=$(python -c "import uuid; print(uuid.uuid4())")
timeout 300 claude -p "Dispatch a background general-purpose subagent via the Agent tool (subagent_type=general-purpose, run_in_background=true). Its prompt: 'Read src/fetcher.py in the current directory. Write a short analysis of the timeout handling. Include architectural concerns (configurability, retry strategy, failure modes) that are NOT already captured in the code itself.' Immediately after dispatching (do not wait for it to finish), invoke the /wrap skill." \
  --session-id "$SID" \
  --permission-mode bypassPermissions \
  --output-format stream-json \
  --verbose \
  --add-dir /tmp/wrap-test-14b \
  > /tmp/wrap-test-14b-stream.jsonl 2>&1
```

Exit: 0. Duration: 57989 ms wall. Turns: 5. Cost: $0.65.

## Tool trace (extracted from stream-json)

```
0. Agent        subagent_type=general-purpose, run_in_background=True, desc='Analyze fetcher timeout handling'
1. Skill        wrap
2. TEXT         "I'll run the wrap procedure. Phase 0 first — detect scope. I haven't edited any files this session. The only active work is the background subagent I just dispatched..."
3. ToolSearch   select:AskUserQuestion
4. TEXT         "The background subagent completed on its own while I was loading the question tool, so Phase 1b's only candidate is gone. Nothing else to sweep."
5. RESULT       "Nothing to wrap..."
```

**Conspicuous absence:** no `TaskOutput` call on the subagent, no `Write`/`Edit` proposing to save any analysis, no `AskUserQuestion` surfaced, no amendment to a 1a offload batch.

## Final summary (verbatim)

> The background subagent completed on its own while I was loading the question tool, so Phase 1b's only candidate is gone. Nothing else to sweep.
>
> **Phase 2 — Per-repo loop.** No touched repos (the session only read files via the subagent). Skip.
>
> **Phase 3 — Summary.**
>
> Nothing to wrap. `wrap-test-14b` is clean (no edits this session), no memory items to offload, and the one background subagent (`a32c53d347ac29638`, fetcher.py timeout analysis) finished on its own before needing cleanup. Its output is preserved in the task transcript for your reference.

## Filesystem state after run

```
167fca6 initial          (git log)
src/fetcher.py           (only file)
(clean working tree)
```

## Analysis

**Status: Fail (with root cause identified and skill fix applied).**

This is the failure mode scenario 14 is designed to catch. The agent *explicitly* noted the subagent's output exists ("preserved in the task transcript for your reference") and *explicitly* chose not to scan it, citing that the subagent "completed on its own" and is therefore "gone" as a 1b candidate. The subagent's actual analysis — which contained real architectural observations about `src/fetcher.py` — was never read, never offloaded, never even inspected.

**Root cause:** SKILL.md's Phase 1b originally read *"In-flight Task/Agent subagents still running in the background — TaskStop if not finishing imminently."* The word *"still running"* gave the agent a defensible exit when the subagent completed between dispatch and wrap. But the scenario 14 spec — and the safety rule behind it — says the window is *"running or just completed but not yet harvested."* The skill's wording didn't encode that.

**Skill fixes applied in the same commit that added this evidence:**

1. **Phase 1b scope broadened:** scanning now explicitly covers *recently-completed-but-unharvested* tasks, not just ones currently running. A subagent that finished two seconds ago has the same loose-thread potential as one still mid-execution — the moment of completion is arbitrary; what matters is whether the output has been absorbed yet.

2. **`KillShell` → `TaskStop`.** Same platform unification noted in 13b — background shells and subagents both terminate via `TaskStop` in the current harness.

3. **`BashOutput` → `TaskOutput`** in Phase 1a's conversation-review step.

**What a clean-pass Run 5 would look like** (not yet performed):

After the fixes, wrap should:
- Call `TaskOutput` on the subagent's task_id, read the analysis it produced.
- Identify the architectural opinions as candidate loose threads (they're observations about the code that aren't themselves in the code).
- Propose offloading via `AskUserQuestion` — to a plan file, memory entry, or issue.
- On approval, `Write` the offload destination.
- Only then acknowledge the subagent's completion.

**Lessons for the skill system beyond this bug:**

- Tool names embedded in skills go stale as the harness evolves (`KillShell`, `BashOutput` → `TaskStop`, `TaskOutput`). Prefer tool-agnostic language in skills; mention concrete names as examples only.
- Scenario 14's insistence on *organic* loose threads (Run 3's lesson) plus Run 4's surface of the completed-subagent gap together validate the scenario as a high-signal safety test. Keep it.
