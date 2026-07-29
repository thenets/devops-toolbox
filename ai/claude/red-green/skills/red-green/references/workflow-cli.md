# Cursor CLI workflow orchestrator

Claude Code can run `~/.claude/workflows/red-green-workflow.js` via the
**Workflow** tool. Cursor `agent` CLI has no Workflow API.

Use this instead:

```
scripts/run_workflow_cli.py --workspace <repo> --bug "…"
# or:
scripts/run_workflow_cli.sh --workspace <repo> --bug-file symptom.txt
```

It mirrors the JS workflow by spawning parallel `agent -p` sub-sessions.

## When to use

Same complexity triggers as Step 0 in `SKILL.md` (unknown root cause, cross-
component, races, thorough request). For simple bugs, stay on the inline loop.

Always marks the work **Complex: yes** and passes `--with-grok` to the
validation panel.

## Phases

| Phase | How |
|-------|-----|
| Investigate | 4 parallel `agent -p --mode ask` (code, history, live, harness) |
| Diagnose | 3 lens hypotheses + 2 refuters each (ask mode); up to 2 rounds |
| Red | write agent + ask verifier (≤3 attempts); uses `run_red.sh` |
| Fix | write agent (product code only) |
| Green | ask verifier + write repair loop; uses `run_green.sh` |
| Validation | `run_adversary_review.sh --with-grok` → evaluate agent → remediate ≤3 |

Artifacts land in `--outdir` (or a temp dir): per-agent JSON/logs,
`worksheet.md`, `panel_rN/AGGREGATE.json`, `REPORT.json`.

## Prerequisites

```
scripts/check_agent_cli.sh   # must exit 0
```

Requires Cursor `agent` on PATH and authenticated (`agent login`).

## CLI

```
run_workflow_cli.py --workspace <repo> \
  --bug "verbatim symptom + known context" \
  [--bug-file path] \
  [--test-command "full suite cmd"] \
  [--live-repro "how to run the product"] \
  [--scripts-dir <this scripts dir>] \
  [--outdir <dir>] \
  [--model <id>] \
  [--max-wait-secs 900] \
  [--dry-run]
```

Env overrides:

- `RED_GREEN_WORKFLOW_MODEL` — default model for sub-agents
- `RED_GREEN_WORKFLOW_MAX_WAIT` — per-agent timeout seconds

Exit codes: `0` skill-done (or panel skipped after green), `1` blocked/failed,
`2` infra, `64` usage.

## Relationship to the JS workflow

| | Claude Code `red-green-workflow.js` | Cursor `run_workflow_cli.py` |
|--|-------------------------------------|------------------------------|
| Runner | Workflow tool (`phase` / `parallel`) | This Python orchestrator |
| Sub-agents | in-process Workflow agents | separate `agent -p` processes |
| Panel | same `run_adversary_review.sh --with-grok` | same |
| Skill Step 0 | prefer Workflow when available | use this when Workflow is missing |

Keep phase prompts aligned when changing either file.
