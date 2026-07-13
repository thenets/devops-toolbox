# Bug worksheet: <short-slug>

Repo: <path> · Date: <date> · Reported as: <verbatim symptom / issue link>

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

## 6. Green

- Red test now passes: <output/exit>
- Full suite for affected module: <command → result>

## 7. Final report (paste into reply)

- Reproduction: …
- Live repro: …
- Red: <test> failed with <assertion> (predicted ✓)
- Fix: …
- Green: <test pass + suite result>
- Caveats / skipped steps and why: …
