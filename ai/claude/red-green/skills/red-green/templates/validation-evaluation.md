# Red-green validation evaluation

Fill this after `AGGREGATE.json` lands (step 6 ran). You are judging the panel,
not restating it. Every finding needs a verdict against the worksheet and repo.

## Subject

- **Bug / symptom:** <!-- one sentence -->
- **Complex?:** yes / no — <!-- reason; Grok on panel? -->
- **Panel models:** opus=`…` · gpt=`…` · grok=`…` / n/a
- **Evidence used:** <!-- worksheet sections, paths, test commands, green output -->
- **Round:** <1–3>
- **Raw aggregate ok:** yes / no · **outdir:** …

## Finding ledger

For each distinct finding (dedupe near-duplicates across models):

| # | Finding (short) | Source | Grounded? | Severity | Verdict | Why |
|---|-----------------|--------|-----------|----------|---------|-----|
| 1 | | all / opus+gpt / opus+grok / gpt+grok / opus / gpt / grok | yes — cite path · no — generic · thin | blocker / should-address / nit / noise | accept / reject / needs-evidence | one line (reject **must** cite path/hunk/command) |

**Grounded?** means: can you point at concrete evidence in the red-green work
(worksheet claim, test file, fix hunk, green command output)? Generic LLM
caution without a hook → `no — generic`.

**Verdict meanings:**
- `accept` — objection is real and material for this fix (enters remediation)
- `reject` — wrong, outdated, or already handled — cite evidence in Why
- `needs-evidence` — plausible, but you/they lack enough signal to decide

Nits alone do not enter the remediation loop. Accepted blockers /
should-address always do.

## Stance sanity check

| Model | ok | reworkStep | Sensible given evidence? | Note |
|-------|----|------------|--------------------------|------|
| opus | | | yes / no / partial | |
| gpt | | | yes / no / partial | |
| grok (if on panel) | | | yes / no / partial | |

If a stance is extreme relative to the evidence, mark `no` and explain.

## Consensus gaps

After dedupe, list material gaps only:

| Gap type | Detail | Material? | Action |
|----------|--------|-----------|--------|
| ok_split / reworkStep_split / none | | yes / no | remediate / ignore-nit / report-needs-evidence |

Material gap = `ok` disagree, or differing earliest `reworkStep` on an
accepted / needs-evidence item. Mild wording differences on one deduped issue
are not a gap.

## Decision

- **Raw panel pass:** yes / no
- **Accepted findings remaining:** <!-- list or none -->
- **Material consensus gap remaining:** yes / no — <!-- which -->
- **Skill-done this round?:** yes (zero accepts, no material gap, raw pass) / no
- **If no — earliest reworkStep:** <1–5 / n/a>
- **Safe to ignore:** <!-- rejected + noise, with one-line why each -->
- **Open questions:** <!-- needs-evidence items -->
