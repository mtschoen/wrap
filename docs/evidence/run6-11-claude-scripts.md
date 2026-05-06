# Scenario 11 — `.claude/scripts/` mixed (Run 6)

**Date:** 2026-05-06
**Skill version:** commit `06f9680`
**Run mode:** `claude -p`, `--permission-mode bypassPermissions`, `--output-format stream-json --verbose`
**Session id:** `08249457-f04e-4e97-bb83-409ac569efe0`
**Cost:** $0.41, 3 turns, 22.5s wall.

## Setup

`/tmp/wrap-run6/s11-scripts/` — git repo with `.claude/scripts/build-once.ps1` (one-off scratch) and `.claude/scripts/keep-me.ps1` (with `# KEEP:` marker). Single initial commit including both scripts. Clean working tree.

## Run command

```bash
timeout 300 claude -p "Invoke the /wrap skill on this directory." \
  --session-id 08249457-f04e-4e97-bb83-409ac569efe0 \
  --permission-mode bypassPermissions \
  --output-format stream-json --verbose \
  --add-dir /tmp/wrap-run6/s11-scripts
```

## Tool trace

```
0. Skill        skill='wrap'
```

## Final summary (verbatim, condensed)

> **Phase 0 — Outstanding asks:** This session has no conversation prior to `/wrap` — nothing was asked, nothing is unfinished.
>
> **Phase 1 — Scope detect:** I haven't edited, created, or run git commands against any repo this session. The cwd is clean on `main` with only the initial commit. No touched repos.
>
> **Phase 2 — Session-wide sweep:** No conversation context to mine for cross-project memory. No background shells, subagents, or monitors started.
>
> **Phases 3 & 4:** Nothing to do.
>
> Per principle 8 (empty sweeps are a pass condition, no ceremony):
>
> Nothing to wrap. `s11-scripts` is clean, no memory to offload, no background processes running.

## Analysis

**Status: Partial — scenario design issue, not a skill defect.**

The skill correctly applied Phase 1's "touched-repo" rule: the session did not edit, create, or run git commands against the repo, so the repo is **not in scope**. With no in-scope repo, Phase 3c (the hygiene path that would have flagged `build-once.ps1` and respected the KEEP marker on `keep-me.ps1`) does not run.

This is consistent with `SKILL.md` Phase 1:

> Recall. Review the conversation and list every path you edited, created, or ran git commands against. **Not in scope:** Repos the session only *read*.

In Run 1, the agent took a more permissive interpretation (cwd implicitly in scope) and exercised Phase 3c. In Run 6, the stricter interpretation skipped it. Both are defensible against current prose; the variance suggests the prose has wiggle room.

**Recommended follow-up:**

- Update `references/pressure-scenarios.md` scenario 11 setup so the test session *touches* the repo first (e.g., "edit `README.md` to add a one-line note, then run `/wrap`"). This makes the repo unambiguously in scope and exercises Phase 3c.
- Or, sharpen `SKILL.md` Phase 1 prose so cwd-when-/wrap-is-invoked is explicitly in scope unless the user excludes it. (Trade-off: the stricter rule prevents accidental wraps of unrelated cwds.)

**Pass criteria not violated:** the skill made no destructive action, did not delete `keep-me.ps1`, and emitted the empty-case summary. The Phase 3c logic is unverified by this run, not refuted.
