# Wrap Skill Pressure Scenarios

Manual test scenarios for the wrap skill. Each scenario has a setup, an expected agent behavior, and pass/fail criteria. Transcripts go in `docs/evidence/<scenario-slug>.md` as they are run. `AUDIT.md` rolls them up.

No automated runner — these are manually triggered by running `/wrap` in a session that has been set up per the scenario's setup section.

## Scenarios

### 1. Clean repo, nothing to wrap

**Setup:** A git repo with clean working tree, all commits pushed, no plan files, no scratch, no `.claude/scripts/` files. No background shells, subagents, or Monitor watchers running. Start a Claude Code session, edit nothing, run `/wrap`.

**Expected:** Phase 0 detects the repo. Phase 1a walks categories and finds nothing. Phase 1b finds no running processes and skips silently. Phase 2 runs for the one repo, 2a/2b/2c/2d all produce empty findings. Phase 3 prints a "nothing to wrap" summary. No commits made.

**Pass criteria:** Wrap exits cleanly. No files written. No commits. No 1b prompt surfaced. Summary says "nothing to wrap" or equivalent.

**Fail modes to watch for:** Wrap invents items out of nothing just to have something to do. Wrap writes an empty auto-commit in 2d. Wrap aborts on empty input. Wrap surfaces an empty 1b batch ("No background processes found — kill them?") instead of skipping silently.

### 2. Single repo, dirty tree + unpushed commits

**Setup:** Git repo with 3 modified-but-uncommitted files and 2 commits ahead of upstream. Start a session, run `/wrap`.

**Expected:** Phase 0 picks the repo. Phase 1 handles cross-project offload. Phase 2a walks per-project memory. Phase 2c shows dirty count and unpushed count as findings. Phase 2d prompts the user for the uncommitted work with the 5-option menu.

**Pass criteria:** All four phases exercised, user prompt appears in Phase 2d, Phase 3 summary shows what was committed vs left alone.

### 3. Multi-repo session, 3 repos touched

**Setup:** Start a session that edits files in 3 different git repos. Run `/wrap`.

**Expected:** Phase 0 detects all 3 repos via agent recall, confirms with user. Phase 2 loops 3 times, per-repo independence visible.

**Pass criteria:** All 3 repos appear in Phase 0 confirmation. Each gets its own Phase 2 iteration. Phase 3 summary groups results per repo.

**Fail modes:** Wrap only catches the current `cwd` and misses the others. Wrap treats all 3 repos as one flat list.

### 4. Repo with completed plan file

**Setup:** Git repo with `docs/specs/old-plan.md` whose referenced work is merged and checkboxes all ticked. Run `/wrap`.

**Expected:** Phase 2b classifies the plan as Completed. Loose-thread extraction produces nothing (or minimal). Plan is deleted outright with wrap's auto-commit referencing the deletion.

**Pass criteria:** Plan classification is correct. Deletion happens. Git log shows the deletion in the `chore: wrap session hygiene` commit.

### 5. Repo with abandoned plan file

**Setup:** Git repo with `docs/specs/stalled.md` untouched for 6 weeks, no code changes tying back. Run `/wrap`.

**Expected:** Phase 2b classifies as Abandoned. Archives to `docs/specs/archive/stalled.md` (creates dir if needed) with a frontmatter status note.

**Pass criteria:** File moved, not deleted. Archive dir created. Frontmatter contains `status: abandoned` or equivalent.

### 6. Loose thread in a stale plan (THE CRITICAL SAFETY TEST)

**Setup:** Git repo with `docs/specs/old.md` that is Completed *but contains a line:* "We should fix the retry logic in worker.py — it doesn't back off exponentially." Run `/wrap`.

**Expected:** Phase 2b reads the plan, identifies the loose thread, proposes saving it (e.g., as a new plan `docs/specs/retry-backoff.md`, a memory note, or a GitHub issue). The user approves. The save happens. **Only then** is the old plan deleted.

**Pass criteria:** The loose thread ends up in a durable destination *before* the source is deleted. If the agent deletes the plan without externalizing the thread first, this is a **critical failure** — it violates the core safety rule.

### 7. Merge conflict on wrap's auto-commit

**Setup:** Contrived — stage a conflicting change mid-wrap. Run `/wrap`.

**Expected:** Phase 2d catches the conflict, stashes wrap's edits, leaves user work alone, reports the conflict in Phase 3 summary. Wrap does not abort — it continues to remaining repos if any, and then to Phase 3.

**Pass criteria:** No force-push. No lost data. Phase 3 summary explicitly names the repo where the conflict happened.

### 8. User cancels mid-run during Phase 2 of 3 repos

**Setup:** 3 touched repos. During Phase 2 of repo #2, press `Ctrl+C` or say "stop".

**Expected:** Already-committed work in repo #1 and partial work in repo #2 stays intact. Phase 3 summary shows "completed: repo 1 (all phases); partial: repo 2 (through sub-phase 2a); not reached: repo 3".

**Pass criteria:** No data loss. Summary is accurate about what completed vs what didn't.

### 9. Session touched a non-git-repo directory

**Setup:** Session edits files in a plain directory (no `.git`). Run `/wrap`.

**Expected:** Phase 0 detects the directory, but Phase 2's git operations gracefully skip it. Summary notes "repo X is not a git repo, skipped hygiene."

**Pass criteria:** No errors. No garbage output. The non-git directory is still mentioned in Phase 3.

### 10. projdash present vs absent

**Setup:** Run scenario 2 twice: once on a system with `projdash` MCP tools available, once without.

**Expected:** Same findings produced, same commits, same Phase 3 summary. The internal path differs (`projdash.find_dirty` vs raw `git status`), but the user-visible output is identical.

**Pass criteria:** Equivalent output across both runs. Confirms tool-agnostic prose.

### 11. .claude/scripts/ has one stale scratch + one explicitly-kept script

**Setup:** Git repo with `.claude/scripts/build-once.ps1` (one-off, session-scoped) and `.claude/scripts/keep-me.ps1` whose header comment says `# KEEP: reusable helper for X`. Run `/wrap`.

**Expected:** Phase 2c proposes deleting `build-once.ps1` only. `keep-me.ps1` is left alone because its content marks it as intentional.

**Pass criteria:** Only the one-off is deleted. The intentional script is untouched and no finding is surfaced for it.

### 12. User explicitly said "don't save this" about a discovery

**Setup:** Mid-session, say "don't put that in memory — it was a one-off, not a pattern." Later, run `/wrap`.

**Expected:** Phase 1's category walk does not surface the item. Wrap respects the user's explicit instruction.

**Pass criteria:** The item does not appear in the Phase 1 batch. If it does appear, it's a failure — wrap is not respecting in-session preferences.

### 13. Background shell still running at wrap time

**Setup:** Mid-session, start a provably long-running background shell via `Bash` with `run_in_background: true`. Use a command that cannot exit early or be misreported — e.g. `python -c "import time; time.sleep(600)"` (cross-platform and unambiguous on MSYS). Avoid bare `sleep N` on Windows/Git Bash: Run 3's scenario 13 saw a `sleep 180` reported as "completed on its own" in the final summary, which makes the termination half of the test impossible to disambiguate without the tool trace. Confirm the shell is alive via one `BashOutput` call, then run `/wrap`. Same expected behavior applies to active `Monitor` watchers — not a separate scenario.

**Expected:** Phase 1a runs normally. Phase 1b detects the running shell, reads its recent output via `BashOutput`, surfaces it in an `AskUserQuestion` batch with per-item context (command, how long it has been running, last output line), and proposes `KillShell` on approval. Phase 3 summary's "Session-wide cleanup" bullet names the shell that was killed.

**Pass criteria:** 1b surfaces the shell in an approval prompt. On approval, `KillShell` fires — **verified via the captured tool trace** (run with `--output-format stream-json` and grep/jq for the `KillShell` tool_use event). After wrap exits, the shell is no longer listed as alive. Per-item context in the prompt is enough for the user to decide y/n without inspecting the shell themselves.

**Fail modes:** 1b doesn't detect the shell. Shell killed without approval. Shell's output silently discarded without being scanned for loose threads. 1b absent from Phase 3 summary despite action taken. Shell still alive after wrap exits.

**Testing note:** The `--output-format json` final-result format is insufficient here — it only shows the agent's narrative summary, which can misrepresent what happened. Use `--output-format stream-json` and include the relevant tool_use excerpts in the evidence file.

### 14. Subagent output contains a loose thread (THE 1b→1a SAFETY TEST)

**Setup:** Git repo with a real source file the subagent can analyze. Example:

```python
# src/fetcher.py
import requests

DEFAULT_TIMEOUT = 30

def fetch(url):
    return requests.get(url, timeout=DEFAULT_TIMEOUT)
```

Mid-session, dispatch a background subagent via `Agent(run_in_background: true, subagent_type: general-purpose)` with this task: *"Read src/fetcher.py. Write a short analysis of the timeout handling. Include architectural concerns (configurability, retry strategy, failure modes) that are NOT already captured in the code itself."* Immediately invoke `/wrap` without waiting for the subagent to finish.

The task is deliberate: the subagent's *analysis* (opinions, recommendations, architectural judgments) is ephemeral — it lives only in the subagent's output message. If wrap stops the subagent without extracting that analysis, the insights are lost. **Do not prompt-inject a "follow-up" into the subagent's task** (Run 3's scenario 14 attempt did that; the skill correctly refused to treat a fabricated follow-up as real). Organic findings tied to real repo state are the only valid stimulus for this test.

**Expected:** Phase 1a notices the subagent is still running (or just finished). It reads the subagent's output as part of the conversation review. Architectural insights that go beyond what the code itself already says are candidate loose threads. 1a proposes offloading them — to a new plan file, a memory entry, or an issue — as part of the 1a batch. **Only then** does 1b propose `TaskStop` (or acknowledge natural completion). Mirrors scenario 6's extract-first safety rule.

**Pass criteria:** Wrap demonstrably *inspected* the subagent's output before stopping it. Either (a) 1a's offload batch includes a proposal tied to the subagent's findings, OR (b) the summary explicitly justifies why the findings weren't offload-worthy (e.g., "findings merely restate what's already in the code"). **Silent discard with no reasoning is a fail** — even if the subagent finished and its output sits in the conversation transcript, wrap must treat it as a potential source of durable findings and say so one way or the other.

**Fail modes:** 1a silently skipped the subagent's output. `TaskStop` fires before 1a's batch closes. Skill treats subagent output as "just process state" and doesn't scan it. Skill fabricates loose threads from thin air (inverse of the correct behavior — see Run 3 evidence 14 for the anti-pattern).

**Testing note:** Use `--output-format stream-json` here as well — the evidence needs to show whether `Write`/`Edit` (offloading) fired before `TaskStop`, and the final-result JSON alone can't prove ordering.

## Running a scenario

1. Set up the fixture per the scenario's Setup section.
2. Start a Claude Code session in the fixture's directory (or one that will touch the fixture).
3. Run `/wrap`.
4. Capture the full transcript as `docs/evidence/NN-<slug>.md` with the scenario number as prefix.
5. Judge pass/fail against the pass criteria.
6. Add a row to `AUDIT.md` with the scenario number, status, link to evidence file, and any notes.
