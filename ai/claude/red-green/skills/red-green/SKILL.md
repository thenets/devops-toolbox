---
name: red-green
description: Fix a bug with red-green discipline in any language or project — reproduce it, write a failing regression test (red), fix, verify green, then (only if Cursor agent CLI is present and authenticated) run a multi-model validation panel (Opus + GPT; add Grok when the bug was hard to reproduce or fix), evaluate findings against evidence, and loop on accepted findings or material consensus gaps until the panel passes. For complex bugs, prefer the multi-agent workflow (Claude Code Workflow tool, or Cursor CLI `scripts/run_workflow_cli.sh` which fans out parallel `agent -p` sessions). TRIGGER whenever a defect is being fixed - a reported bug, crash, panic, hang, freeze, flaky test, race, regression, wrong output, "this doesn't work", or an error from logs/CI/Sentry. If the current project has its own red-green or bugfix skill, that skill takes precedence over this one. Do NOT trigger for new features, refactors, or docs.
---

# Red-green bug fixing (general)

A bug that had no test is a bug that can come back. Every bug fix lands with a
test that fails before the fix and passes after it — in that order, observed,
never assumed — and then survives a multi-model validation panel with an
evidence-bound evaluation ledger (and a remediation loop on accepted findings
or material consensus gaps).

Fill in `templates/bug-worksheet.md` (copy it into your scratchpad) as you go;
it is the skeleton of the final report and keeps you honest at each gate.

## Step 0 — Size the bug (inline vs. workflow)

Handle the bug **inline** (steps 1–8 below) by default. Invoke the companion
**workflow** instead when the bug is genuinely complex — any of:

- root cause still unknown after your first focused investigation pass,
- several symptoms that may or may not share one cause,
- the bug spans components/processes (client+server, daemon+CLI, UI+backend),
- a race / heisenbug / only-in-production failure,
- the user asked for a thorough or exhaustive job.

Pick the runner that exists in your host:

### A) Claude Code — Workflow tool

If the **Workflow** tool is available, call the saved workflow
`red-green-workflow` (installed at `~/.claude/workflows/red-green-workflow.js`;
this skill instructing the call counts as the user's opt-in to multi-agent
orchestration):

```
Workflow({
  name: "red-green-workflow",
  args: {
    bug: "<verbatim symptom + everything already known>",
    repoPath: "<absolute repo root>",
    scriptsDir: "<absolute path to>/.claude/skills/red-green/scripts",
    testCommand: "<full-suite command, if known>",
    liveRepro: "<how to run/observe the real product, if known>"
  }
})
```

### B) Cursor CLI — `agent -p` orchestrator

Cursor `agent` has **no** Workflow tool. Use the CLI port that fans out the
same phases via parallel `agent -p` sessions:

```
scripts/run_workflow_cli.sh --workspace <absolute repo root> \
  --bug "<verbatim symptom + everything already known>" \
  [--test-command "<full-suite command>"] \
  [--live-repro "<how to run/observe the product>"] \
  [--outdir <dir>]
```

Details: [references/workflow-cli.md](references/workflow-cli.md).

Either workflow runs investigate → diagnose (adversarially verified) → red →
fix → green → validation panel with **Grok** (always complex on this path) →
evaluate → consensus-gap remediations loop, and returns a structured report
(`REPORT.json` for the CLI port). Relay that report to the user; verify its
green claim yourself (one `run_green.sh` call) and confirm the evaluated panel
is done (`skillDone` / no accepted findings / no material consensus gap) before
presenting the fix as done.

When the workflow path is used, mark the worksheet **Complex: yes**.

## The loop (inline)

### 1. Reproduce the behavior

State, in one sentence, the exact input/state that produces the wrong output.
If you cannot state it, you have not found the bug — keep reading code, add
logging, run the failing path. Never skip to a fix on a hypothesis.

- For a freeze/stall, "reproduction" means naming the stuck frame (stack
  sample, `ps`, `lsof`, thread dump), not an input.
- Suspect one cause behind several reports: before fixing symptoms separately,
  ask what single failure would produce all of them.

### 2. Reproduce in a live environment

Reproduce in the running product before theorizing from source, whenever the
product can run. Static reading regularly finds nothing wrong while the running
app is provably broken. Interrogate the live system: logs, side effects
(child processes, file writes, network calls), process state. Also check the
deployed/running artifact against the source — "works in tests, broken in the
app" is often a stale binary, not a code bug. See
[references/live-repro.md](references/live-repro.md) for tactics per surface
(CLI, server, UI, daemon).

If the product genuinely cannot run here (needs prod credentials, real
hardware), say so in the worksheet and proceed on the strongest evidence you
have (logs, core dumps, user report).

### 3. Create the red test

Write a test that asserts the **correct** behavior, at the cheapest tier that
actually exercises the bug (unit before integration before e2e). Find the
project's test conventions first — run `scripts/detect_stack.sh <repo-root>`
if they aren't documented in CLAUDE.md/README/CI config.

- Name it after the bug, not the function (`test_retry_does_not_drop_last_chunk`,
  not `test_retry_2`). Assert the behavior, not the implementation.
- **Predict, then run, then watch it fail.** Before running, write the exact
  expected failure into the worksheet. Then verify with:

  ```
  scripts/run_red.sh -p '<regex matching the predicted assertion failure>' -- <test command>
  ```

  Keep `-p` **tight** — match the specific assertion/message you predicted
  (e.g. `assert 'release' == 'release-2024'`). Do **not** OR in generic tokens
  like `AssertionError` or `FAILED`; that makes unrelated failures look "predicted"
  and the validation panel will (correctly) reject the red gate.

  The script fails the gate if the test passes, if it fails without matching
  your prediction, or if the failure smells like a compile/build error —
  **a compile error is not a red**, and neither is a setup crash.
- If the red test cannot exist before the fix (it needs a new function/param
  to even compile), use the surgical-revert procedure in
  [references/revert-red.md](references/revert-red.md).
- If the bug is a race or otherwise non-deterministic, test the invariant the
  fix establishes, not the race itself — see
  [references/nondeterministic.md](references/nondeterministic.md).
- If the bug is genuinely untestable at any tier, say so explicitly, explain
  why, and get the user's agreement before fixing without a test. Rare escape
  hatch, not a default.

### 4. Fix the bug

Change product code only. **Never edit the test to make it pass.** Prefer the
minimal fix that addresses the root cause over one that suppresses the symptom.

### 5. Check green

```
scripts/run_green.sh -- <same test command>     # the red test now passes
scripts/run_green.sh -- <full suite command>    # the fix broke nothing
```

Run the full suite for the affected module/project, not just the new test.
Follow the project's own conventions for committing (some repos want test +
fix in one commit — that is what makes the test a regression guard).

### 6. Validation panel (`agent` CLI)

**Prerequisite:** Cursor `agent` CLI present **and** authenticated. Check first:

```
scripts/check_agent_cli.sh
```

- Exit 0 → proceed with this step.
- Exit nonzero → **skip steps 6, 7, and 8**. Note the skip in the worksheet/report.
  Do **not** invent a local substitute review, and do **not** enter the
  remediation loop. Steps 1–5 remain the definition of done when the CLI gate fails.

**Complexity → Grok:** Mark the worksheet `Complex: yes` (and pass `--with-grok`)
when any of these hold:

- live repro was hard / partial / substituted with logs/cores,
- root cause unknown after the first focused investigation pass,
- fix required more than one substantive product-code attempt before green,
- race / heisenbug / cross-component / only-in-production,
- user asked for thorough/exhaustive, or the workflow path was used.

Otherwise keep the default dual panel (Opus + GPT).

When the gate passes, run the validation panel via the Cursor `agent` CLI —
**latest Opus** and **latest flagship GPT**, plus **latest Grok** when complex
(resolved at runtime, not hardcoded):

```
scripts/run_adversary_review.sh --workspace <repo-root> \
  --context-file <filled-worksheet-or-summary.md> \
  [--bug-file <symptom.txt>] \
  [--with-grok]
```

Details, model resolution, consensus fields, and overrides:
[references/validation-panel.md](references/validation-panel.md).

Record models used, raw aggregate `ok`, findings, and `reworkStep` in the
worksheet. Aggregate exit 3 means skipped (same as failed `check_agent_cli.sh`)
— not a rejection. Raw exit 0/1 is **not** the end of the skill: always continue
to step 7 when the panel actually ran.

### 7. Evaluate panel (mandatory when step 6 ran)

You are the facilitator **and** the evaluator. Collecting panel JSON is not
done — judge each finding against the worksheet and repo evidence.

Copy `templates/validation-evaluation.md` and fill it. Follow
[references/validation-panel.md](references/validation-panel.md#evaluate):

- Dedupe near-duplicate findings across models.
- For each: grounded? severity? verdict (`accept` / `reject` / `needs-evidence`)?
- Reject requires a one-line evidence citation (path/hunk/command). Bare "noise"
  without a hook is invalid.
- Sanity-check each model's `ok` / `reworkStep` against the actual work.
- List **consensus gaps**: `ok` splits, or material `reworkStep` splits after dedupe.

Do not dump raw panel output as the answer. Do not rubber-stamp or reflexively
dismiss the panel — every verdict needs a one-line why tied to evidence.

### 8. Consensus-gap remediation loop

**Only if step 6 actually ran** (agent CLI present + authenticated) **and**
evaluation found either:

1. any `accept` finding, **or**
2. a material consensus gap (`ok` disagree across panelists, or differing
   earliest `reworkStep` on an accepted / needs-evidence item).

Never enter this step when the CLI gate skipped the panel.
Nits alone do not enter the loop.

When remediation is required:

1. Read the evaluation ledger + `AGGREGATE.json` — note earliest `reworkStep`
   (1–5) among accepted / material-gap items and the findings.
2. Investigate those findings in the repo (do not argue with them only in prose).
3. Return to that earlier step and redo work forward through step 5.
4. Re-run step 6 (same complexity → Grok rule; only if `check_agent_cli.sh`
   still passes), then step 7 again.

Repeat until the skill-done criteria hold, or after **3** panel rounds stop and
report the blocking accepted findings / open gaps to the user — never force a
pass by ignoring them.

**Skill done** (latest round): evaluation has zero `accept` findings, no
material consensus gap, and raw panel pass (all panelists `ok=true`).

**Blocked:** 3 rounds exhausted with remaining accepts/gaps → report; do not
claim verified. `needs-evidence` that cannot be settled → report to the user;
do not force pass.

Rework map: `1` reproduction · `2` live repro · `3` red test · `4` fix ·
`5` green check. Always resume from the earliest implicated step.

## Reporting

The final message states plainly:

- the one-sentence reproduction (for a freeze: the evidence and stuck frame),
- whether it was reproduced live, and how,
- complex?: yes/no and why (and whether Grok joined the panel),
- the red run — test name + the assertion that failed (predicted vs observed),
- the fix (files + mechanism),
- the green run — test pass + full-suite result,
- the validation panel — models used, raw aggregate ok, evaluated ledger
  (accepted vs rejected findings), consensus gaps closed or still open;
  **or** explicitly skipped because Cursor `agent` was missing/unauthenticated;
  **or** blocking findings + which step you looped to.

If any of those did not happen, say which and why. Never present a fix as
verified when the red step was skipped. If the panel was skipped for the CLI
gate, say so plainly — do not claim multi-model review passed.
