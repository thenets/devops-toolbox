---
name: red-green
description: Fix a bug with red-green discipline in any language or project — reproduce it, write a failing regression test (red), fix, verify green. TRIGGER whenever a defect is being fixed - a reported bug, crash, panic, hang, freeze, flaky test, race, regression, wrong output, "this doesn't work", or an error from logs/CI/Sentry. If the current project has its own red-green or bugfix skill, that skill takes precedence over this one. Do NOT trigger for new features, refactors, or docs.
---

# Red-green bug fixing (general)

A bug that had no test is a bug that can come back. Every bug fix lands with a
test that fails before the fix and passes after it — in that order, observed,
never assumed.

Fill in `templates/bug-worksheet.md` (copy it into your scratchpad) as you go;
it is the skeleton of the final report and keeps you honest at each gate.

## Step 0 — Size the bug (inline vs. workflow)

Handle the bug **inline** (steps 1–5 below) by default. Invoke the companion
**workflow** instead when the bug is genuinely complex — any of:

- root cause still unknown after your first focused investigation pass,
- several symptoms that may or may not share one cause,
- the bug spans components/processes (client+server, daemon+CLI, UI+backend),
- a race / heisenbug / only-in-production failure,
- the user asked for a thorough or exhaustive job.

To invoke it, call the Workflow tool with the saved workflow
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

The workflow runs investigate → diagnose (adversarially verified) → red → fix →
green → review, and returns a structured report. Relay that report to the user;
verify its green claim yourself (one `run_green.sh` call) before presenting the
fix as done.

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

## Reporting

The final message states plainly:

- the one-sentence reproduction (for a freeze: the evidence and stuck frame),
- whether it was reproduced live, and how,
- the red run — test name + the assertion that failed (predicted vs observed),
- the fix (files + mechanism),
- the green run — test pass + full-suite result.

If any of those did not happen, say which and why. Never present a fix as
verified when the red step was skipped.
