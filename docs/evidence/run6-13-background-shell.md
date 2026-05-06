# Scenario 13 — Background shell at wrap time (Run 6)

**Date:** 2026-05-06
**Skill version:** commit `06f9680`
**Run mode:** `claude -p`, `--permission-mode bypassPermissions`, `--output-format stream-json --verbose`
**Session id:** `fb5278ad-5ac2-4da3-8332-61e92d250d51`
**Cost:** $0.90, 9 turns, 62.5s wall.

## Setup

`/tmp/wrap-run6/s13-bg/` — clean git repo with single initial commit. Prompt instructs the agent to start a `python -c "import time; time.sleep(600)"` background shell, confirm via `TaskOutput`, then invoke `/wrap`.

## Run command

```bash
timeout 360 claude -p "Start a provably long-running background shell using the Bash tool with run_in_background=true. Command: python -c \"import time; time.sleep(600)\". After the shell is dispatched, call TaskOutput once to confirm it's alive. Then invoke the /wrap skill." \
  --session-id fb5278ad-5ac2-4da3-8332-61e92d250d51 \
  --permission-mode bypassPermissions \
  --output-format stream-json --verbose \
  --add-dir /tmp/wrap-run6/s13-bg
```

## Tool trace

```
0. Bash         cmd='python -c "import time; time.sleep(600)"'  run_in_background=true
1. ToolSearch   q='select:TaskOutput'
2. TaskOutput   id='bf36xv4va'    → confirms alive
3. Skill        wrap
4. ToolSearch   q='select:AskUserQuestion,TaskStop'
5. AskUserQuestion  Q='Background task bf36xv4va is running python -c "import time; time.sleep(600)" — a 10-minute sleep with no useful output. Wrap...'
                    OPTS=['Stop it', 'Leave it running']
6. TaskStop     id='bf36xv4va'   ★★★ TERMINATION ★★★
```

## Final summary (verbatim)

> Background task stopped. No repos in scope, so Phase 3 is empty. Going to Phase 4.
>
> ---
>
> **Wrap summary**
>
> - Nothing to wrap. No repos touched, no memory items to offload, no plans or hygiene findings.
> - Background cleanup: stopped `bf36xv4va` (`python -c "import time; time.sleep(600)"`).
>
> Session was wrap-procedure exercise only — no domain work to externalize.

## Analysis

**Status: Pass.** End-to-end exercise of Phase 2b's detection + termination paths under the post-renumber Phase 0 skill.

**What passed (verified via tool trace, not just narrative):**

- Phase 2b enumerated the running task via `TaskOutput` (event 2).
- Phase 2b surfaced an `AskUserQuestion` batch with per-item context (event 5: command, age implied, output state).
- `TaskStop` fired on event 6 — termination path demonstrably exercised.
- Final summary's "Background cleanup" line names the stopped task.

**Bypass-mode AskUserQuestion behavior:** with 2 options ("Stop it" / "Leave it running"), bypass auto-selected the first option ("Stop it") — consistent with Run 4's 13b evidence. No regression on the renumbered Phase 2b path.

**Renumber check:** the skill correctly uses Phase 2b (post-Phase-0 numbering) without confusion. Phase 0 fired silently first (no fork), then Phase 1 found no in-scope repo (the session only ran a Bash for the test shell, not against the repo), then Phase 2b detected and terminated the shell.

**Tool-name posture:** agent loaded `TaskOutput`, `AskUserQuestion`, `TaskStop` via `ToolSearch` — no dead-end search for `KillShell` / `BashOutput`. Run 4 fix held.
