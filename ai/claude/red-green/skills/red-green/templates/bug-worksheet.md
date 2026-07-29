# Bug worksheet: <short-slug>

Repo: <path> · Date: <date> · Reported as: <verbatim symptom / issue link>

**Complex?:** <yes/no> — reason: <live-repro hard / root cause unclear / multi-attempt fix / race / cross-component / thorough request / workflow / …>
(If yes → pass `--with-grok` to the validation panel.)

## 1. Reproduction (behavior)

One sentence — exact input/state → wrong output:

> …

For a freeze/stall: the stuck frame (stack sample / thread dump excerpt):

> …

Single-cause check: could other open symptoms share this cause? <yes/no — which>

## 2. Live reproduction

- [ ] Reproduced in the running product
- Command/steps: …
- Observed output/evidence: …
- Running artifact matches source (version/mtime checked): <yes/no>
- If not reproducible live: why, and what evidence stands in for it: …

## 3. Root cause

`file:line` + mechanism (why the code produces the observed behavior):

> …

Hypotheses considered and refuted: …

## 4. Red

- Test name(s) + file: …
- Test command: …
- Tier: <unit / integration / e2e> — why the cheapest that can fail: …
- **Predicted failure (written BEFORE the run):** …
- Observed red output (must match prediction; compile error ≠ red):

```
…
```

- Mode: <test-first red / red-verified by surgical revert / invariant+guard (non-deterministic)>

## 5. Fix

Files changed + mechanism (product code only; tests untouched after red):

> …

Substantive product-code attempts before green: <1 / 2+ — if 2+, mark Complex>

## 6. Green

- Red test now passes: <output/exit>
- Full suite for affected module: <command → result>

## 7. Validation panel (`agent` CLI)

- CLI gate (`scripts/check_agent_cli.sh`): <pass / skip — reason>
- If skipped: stop here (do **not** fill evaluation / remediation below)
- Complex → Grok: <yes — `--with-grok` / no — dual only>
- Command: `scripts/run_adversary_review.sh --workspace … --context-file … [--with-grok]`
- Models resolved: Opus=`…` · GPT=`…` · Grok=`…` / n/a
- Round: <1–3>
- Raw aggregate ok: <yes/no/skipped>
- Findings (raw): …
- reworkStep (raw earliest, if any): <1–5 / none>
- Outdir / AGGREGATE.json: …

## 8. Evaluation ledger (only if panel ran)

Fill `templates/validation-evaluation.md`, then summarize:

- Accepted findings: <none / list>
- Rejected (with evidence cite): <none / list>
- Needs-evidence: <none / list>
- Material consensus gap: <none / ok_split / reworkStep_split — detail>
- Skill-done this round?: <yes/no>
- Earliest reworkStep if remediating: <1–5 / none>

## 9. Remediation loop (only if evaluation requires it)

Enter when panel ran **and** evaluation has accepted findings or a material
consensus gap. Do **not** enter when the CLI gate skipped the review. Nits alone
do not count.

For each failed round: accepted/gap → step returned to → what changed → re-green → re-panel → re-evaluate.

| Round | reworkStep | Accepted / gap | What we changed | Panel + eval result |
|-------|------------|----------------|-----------------|---------------------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

## 10. Final report (paste into reply)

- Reproduction: …
- Live repro: …
- Complex / Grok: …
- Red: <test> failed with <assertion> (predicted ✓)
- Fix: …
- Green: <test pass + suite result>
- Validation panel: models … · raw ok · evaluated accepts/rejects · gaps …
  / OR skipped (CLI gate) / OR blocked on …
- Caveats / skipped steps and why: …
