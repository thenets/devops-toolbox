---
name: opinion
description: Get an adversarial second opinion from the codex CLI (GPT) on a topic, design, implementation, or bug fix. Use when the user says /opinion or asks for a second or adversarial opinion from codex.
argument-hint: [topic, files, diff, or question - defaults to the current working-tree diff]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

# Adversarial second opinion via codex

Ask the `codex` CLI (OpenAI) for an **adversarial** review of a topic, design decision,
implementation, or bug fix, then reconcile its findings with your own judgment. The value is
the disagreement: codex is prompted to attack the work, and you triage what survives.

Model policy: always run the **latest model at `high` reasoning effort**. Check
`~/.codex/models_cache.json` (first entry, described as "Latest frontier ... model") if unsure;
as of 2026-07 that is `gpt-5.6-sol`. Update the `-m` flag below when a newer model ships.

## Steps

### 1. Determine the review subject

- If `$ARGUMENTS` names files, a commit, a topic, or a question, that is the subject.
- If `$ARGUMENTS` is empty, default to the current working-tree changes: `git diff HEAD` (plus
  untracked files via `git status --short`). If the tree is clean, use the last commit
  (`git show HEAD`).
- Gather just enough context yourself (Read/Grep) to write a precise prompt. Do NOT paste whole
  files into the prompt when codex can read them itself: it runs with read access to the repo,
  so give it file paths and line ranges instead. Inline only what isn't on disk (the diff, your
  reasoning, the bug description).

### 2. Write the prompt file

Write the prompt to the scratchpad directory (e.g. `<scratchpad>/opinion-prompt.md`) with this
shape:

```markdown
You are an adversarial senior reviewer. Your job is to find what is WRONG with the
following <design | implementation | bug fix | claim>, not to be agreeable.

IMPORTANT: You are strictly read-only. NEVER change, create, or delete any file, and never
run commands that mutate state (no editing, no git commit/checkout, no builds that write).
Only read and investigate. Report findings as text.

## Subject
<the topic/question, the diff, or file paths + line ranges to read>

## Context
<constraints, prior decisions, why it was done this way: 2-6 bullets>

## Your task
- Actively try to refute the approach: correctness bugs, unhandled edge cases, race
  conditions, security issues, simpler alternatives, hidden costs.
- Read the referenced files before judging. Cite findings as file:line.
- Rank findings by severity. For each, state a concrete failure scenario.
- If something is genuinely fine, say so briefly; do not invent problems to fill space.
- End with a verdict: SHIP | SHIP WITH FIXES | RETHINK, plus a one-line justification.
```

### 3. Run codex

```bash
codex exec --sandbox read-only --color never \
  -m gpt-5.6-sol -c model_reasoning_effort='high' \
  -o <scratchpad>/opinion-out.md \
  - < <scratchpad>/opinion-prompt.md
```

- codex must never modify anything: always pass `--sandbox read-only` (enforcement) AND keep
  the read-only instruction in the prompt (so it doesn't waste the run attempting writes).
  Never use `--sandbox workspace-write`, `danger-full-access`, or
  `--dangerously-bypass-approvals-and-sandbox` in this skill.
- Run from the repo root so codex can read the referenced files.
- Use a generous Bash timeout (600000 ms): high effort can take several minutes.
- The final answer lands in `opinion-out.md` (stdout also shows progress); read the file.
- For a follow-up round (e.g. to challenge one of its findings), use
  `codex exec resume --last "<follow-up>"` with the same `-o` flag.

### 4. Triage and report

Do not just relay codex's output. For each finding, verify it against the code and mark it:

- **Agree**: real issue; say what the fix would be.
- **Disagree**: explain why it's wrong or doesn't apply (cite code).
- **Uncertain**: worth a test or a closer look.

Report to the user: codex's verdict, the triaged findings (most severe first), and your own
bottom line where you and codex disagree. Only propose fixes; don't apply them unless the
user asks.
