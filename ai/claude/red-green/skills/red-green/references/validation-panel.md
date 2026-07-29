# Validation panel (Cursor `agent` CLI)

After green, do **not** present multi-model review as done until the panel
passes **and** you have evaluated findings against evidence — **but only when
the Cursor `agent` CLI is present and authenticated**. This covers steps 6–8
of the loop.

## CLI gate (required before steps 6–8)

```
scripts/check_agent_cli.sh
```

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | `agent` on PATH + authenticated | Run step 6 (then 7; 8 only if evaluation requires remediations) |
| 1 | `agent` not on PATH | **Skip** steps 6–8; note in report |
| 2 | installed but not logged in | **Skip** steps 6–8; suggest `agent login` |

Never enter step 8 when the gate failed. Never substitute an in-process model
review for the skipped CLI review.

`run_adversary_review.sh` runs this check first and exits **3** when skipped.

## Complexity → Grok

Default panel: **Opus + GPT**.

Add **Grok** (`--with-grok` or `RED_GREEN_WITH_GROK=1`) when the worksheet marks
the bug **Complex: yes** for any of:

- live repro was hard / partial / substituted with logs/cores
- root cause unknown after the first focused investigation pass
- fix required more than one substantive product-code attempt before green
- race / heisenbug / cross-component / only-in-production
- user asked for thorough/exhaustive, or the workflow path was used

Otherwise keep dual Opus+GPT.

## What runs

```
scripts/run_adversary_review.sh --workspace <repo-root> \
  --bug-file <optional symptom.txt> \
  --context-file <worksheet-or-summary.md> \
  [--with-grok]
```

The script:

1. Resolves models via `scripts/resolve_review_models.sh` (parses `agent models`):
   - always: latest Opus + latest flagship GPT
   - when `--with-grok`: also latest Grok
   Overrides: `RED_GREEN_OPUS_MODEL`, `RED_GREEN_GPT_MODEL`,
   `RED_GREEN_GROK_MODEL`, or `--opus-model` / `--gpt-model` / `--grok-model`.
2. Launches panelists in parallel with `agent -p --mode ask` (read-only).
3. Requires each to return JSON
   `{ ok, findings, reworkStep, reworkReason, summary }`.
4. Aggregates into `AGGREGATE.json` with `panel`, per-model verdicts, and
   `consensus` (`ok_agree` / `ok_split`, per-model `reworkStep`, `earliest`).
   Exit 0 only if **every** panelist `ok=true` and findings empty (raw pass).

On this machine today that typically resolves to something like
`claude-4.6-opus-max-thinking` + `gpt-5.4-xhigh` (+ `cursor-grok-4.5-high`
when Grok is enabled) — but always resolve at runtime; do not hardcode model
IDs in the skill body.

Raw exit 0/1 is **not** skill-done. Always run the evaluation step when the
panel actually ran.

## Context file

Feed the reviewers everything claimed so far (the filled worksheet is ideal):

- one-sentence reproduction
- complex?: yes/no + reason
- live repro steps + evidence (or why impossible)
- red test path/name/command, predicted vs observed failure
- fix files + mechanism
- green commands + results

Sparse context makes them reject — that is intended.

## Evaluate {#evaluate}

Mandatory when step 6 ran. Fill `templates/validation-evaluation.md`.

You are judging the panel against the worksheet and repo — not restating it.
External models hallucinate risk, over-generalize, and miss project
conventions. Filter that against evidence.

### Ground each finding

For every distinct finding (dedupe near-duplicates across models):

1. **Locate** — Can you cite a file, hunk, command, or worksheet claim the
   finding refers to?
2. **Check** — Is the finding factually true against that evidence?
3. **Weigh** — Even if true, does it matter for red-green correctness?
4. **Verdict** — `accept` / `reject` / `needs-evidence`.

Reject findings that are:

- generic (“consider edge cases”, “add more tests”) with no pointer into the work
- already addressed in the fix/test/worksheet
- based on wrong assumptions about the stack or conventions
- disproportionate (security panic on a comment-only change)

**Reject requires a one-line evidence citation** (path/hunk/command). Bare
"noise" without a hook is invalid — that is how we neutralize facilitator
conflict of interest.

Accept findings that are:

- tied to a concrete path/behavior in the red-green work
- material to reproduction honesty, red-gate integrity, root-cause fix,
  or green claims
- agreed by multiple models *and* confirmed by your read of the evidence
  (single-model findings can still be accepted if clearly grounded)

Prefer findings about:

- weak/wrong reproduction
- missing/unconvincing live repro when feasible
- loose `run_red.sh -p` patterns, compile-as-red, test softened after red
- symptom masks instead of root-cause fixes
- false green claims / suite gaps

Discount style nits unless they violate a stated project standard. Nits alone
do not enter the remediation loop.

### Consensus gaps

After dedupe, a **material consensus gap** is any of:

- (a) `ok` split across panelists (`consensus.ok_split`)
- (b) an `accept` finding from any model (accepted findings always remediate)
- (c) earliest `reworkStep` differs across panelists on an accepted or
    `needs-evidence` item

Mild severity wording differences on the same deduped issue are **not** a gap.
Shared agreement that is generic or wrong against evidence can still be
`reject`ed — consensus is not automatic truth.

### Stance sanity

Include a row per panelist (2 or 3). If a stance is extreme relative to the
evidence (e.g. `ok=false` / `reworkStep=1` when reproduction is solid and
recorded), mark `no` / `partial` and explain.

## Pass / fail definition

| State | Meaning |
|-------|---------|
| **Panel raw pass** | All panelists `ok=true`, findings empty (script exit 0) |
| **Skill done** | Latest round: zero `accept` findings, no material consensus gap, **and** raw panel pass |
| **Blocked** | 3 rounds exhausted with remaining accepts/gaps — report; do not claim verified |
| **Skipped** | CLI gate failed — steps 1–5 only; say panel was skipped |

With Grok: majority `ok` is **not** enough if any *accepted* finding remains.
Without Grok: both must `ok` after evaluation clears accepts/gaps.

`needs-evidence` that cannot be settled → report to the user; do not force pass.

## Rework steps (step 8)

**Prerequisite:** step 6 ran for real (CLI gate passed) **and** evaluation
found accepted findings or a material consensus gap. If the review was skipped
(gate fail / exit 3), stop — there is nothing to remediate under this step.

If remediation is required, read earliest `reworkStep` among accepted /
material-gap items:

| Step | Meaning | What you do |
|------|---------|-------------|
| 1 | Reproduction weak/wrong | Re-establish the failing input/state before touching code |
| 2 | Live repro missing/unconvincing | Reproduce in the running product (or document impossibility) |
| 3 | Red test inadequate | Strengthen/replace the red; re-confirm with `run_red.sh` |
| 4 | Fix wrong or incomplete | Fix product code only; never weaken the test |
| 5 | Green claim false / suite gap | Re-run `run_green.sh` on red test + affected suite |

Then **replay forward** from that step through green, run the validation panel
again (same complexity → Grok rule), and re-evaluate. Cap at 3 full panel
rounds; if still failing, stop and report the blocking findings to the user
instead of forcing a pass.

## Rules

- Panel agents are read-only (`--mode ask`). They must not edit the tree.
- You (the fixer) apply remediations; then re-gate red/green as needed.
- Never delete or soften findings to get exit 0 / skill-done.
- Infra failures during an *authenticated* review (unparseable JSON, agent crash)
  are **not** a pass — fix the runner or re-run; do not skip the gate quietly.
- Missing/unauthenticated `agent` is a deliberate **skip** of steps 6–8 (exit 3),
  not a pass and not a rejection — do not enter step 8.
- Expect sharp eyes on the red gate: a loose `run_red.sh -p` pattern (e.g.
  matching any `AssertionError`) is a common reject with `reworkStep=3`.
