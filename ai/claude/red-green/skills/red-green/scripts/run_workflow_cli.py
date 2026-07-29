#!/usr/bin/env python3
"""run_workflow_cli.py — Cursor CLI port of red-green-workflow.js

Claude Code's Workflow tool cannot run under Cursor `agent`. This orchestrator
mirrors the same phases by fanning out parallel `agent -p` sub-sessions:

  Investigate (4× ask, parallel)
  → Diagnose (3 lenses × hypothesis + 2 refuters)
  → Red → Fix → Green
  → Validation panel (`run_adversary_review.sh --with-grok`)
  → Evaluate + consensus-gap remediation (≤3 rounds)

Usage:
  run_workflow_cli.py --workspace <repo> --bug "..." \\
    [--bug-file f] [--test-command cmd] [--live-repro text] \\
    [--scripts-dir dir] [--outdir dir] [--model id] \\
    [--max-wait-secs N] [--dry-run]

Exit codes:
  0  skill-done (or panel skipped after green — steps 1–5 done)
  1  failed / blocked (undiagnosed, no-red, not-green, panel blocked)
  2  infra (agent CLI missing/unauthenticated, runner error)
  64 usage
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_MAX_WAIT = 900


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f">>> {msg}", flush=True)


def die(msg: str, code: int = 1) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def extract_json(text: str) -> dict[str, Any] | None:
    if not text:
        return None
    m = re.search(r"```json\s*([\s\S]*?)```", text)
    blob = m.group(1).strip() if m else text
    start = blob.find("{")
    end = blob.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        data = json.loads(blob[start : end + 1])
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def run_cmd(
    argv: list[str],
    *,
    cwd: Path | None = None,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def check_agent_cli(scripts_dir: Path) -> None:
    gate = scripts_dir / "check_agent_cli.sh"
    if not gate.is_file():
        die(f"missing {gate}", 2)
    cp = run_cmd([str(gate)])
    if cp.returncode != 0:
        sys.stderr.write(cp.stderr or cp.stdout or "agent CLI gate failed\n")
        die("Cursor agent CLI missing or not authenticated — run: agent login", 2)
    log((cp.stdout or "").strip() or "agent CLI ok")


def run_agent(
    *,
    label: str,
    prompt: str,
    workspace: Path,
    outdir: Path,
    model: str | None,
    mode: str | None,
    write: bool,
    max_wait: int,
) -> dict[str, Any] | None:
    """Spawn one `agent -p` session; return parsed JSON object from result."""
    raw_path = outdir / f"{label}.raw.json"
    log_path = outdir / f"{label}.log"
    prompt_path = outdir / f"{label}.prompt.txt"
    prompt_path.write_text(prompt, encoding="utf-8")

    argv = [
        "agent",
        "-p",
        "--workspace",
        str(workspace),
        "--trust",
        "--sandbox",
        "disabled",
        "--output-format",
        "json",
    ]
    if model:
        argv.extend(["--model", model])
    if mode:
        argv.extend(["--mode", mode])
    if write:
        argv.append("--force")

    # Prompt as final arg (agent treats remaining args as prompt).
    argv.append(prompt)

    log(f"start {label} mode={mode or 'agent'} write={write}")
    t0 = time.time()
    try:
        cp = run_cmd(argv, timeout=max_wait)
    except subprocess.TimeoutExpired:
        log_path.write_text(f"timed out after {max_wait}s\n", encoding="utf-8")
        log(f"FAIL {label}: timeout")
        return None

    raw_path.write_text(cp.stdout or "", encoding="utf-8")
    log_path.write_text(cp.stderr or "", encoding="utf-8")
    elapsed = int(time.time() - t0)

    if cp.returncode != 0:
        log(f"FAIL {label}: agent exit {cp.returncode} ({elapsed}s)")
        return None

    result_text = ""
    try:
        envelope = json.loads(cp.stdout or "{}")
        result_text = envelope.get("result") or ""
    except json.JSONDecodeError:
        result_text = cp.stdout or ""

    data = extract_json(result_text)
    if data is None:
        log(f"FAIL {label}: unparseable JSON ({elapsed}s)")
        (outdir / f"{label}.result.txt").write_text(result_text[:8000], encoding="utf-8")
        return None

    (outdir / f"{label}.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    log(f"done {label} ({elapsed}s)")
    return data


def parallel_agents(
    jobs: list[dict[str, Any]],
    *,
    workspace: Path,
    outdir: Path,
    model: str | None,
    max_wait: int,
) -> list[tuple[str, dict[str, Any] | None]]:
    results: list[tuple[str, dict[str, Any] | None]] = []

    def _one(job: dict[str, Any]) -> tuple[str, dict[str, Any] | None]:
        data = run_agent(
            label=job["label"],
            prompt=job["prompt"],
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode=job.get("mode"),
            write=bool(job.get("write")),
            max_wait=max_wait,
        )
        return job["label"], data

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(jobs))) as pool:
        futs = [pool.submit(_one, j) for j in jobs]
        for fut in concurrent.futures.as_completed(futs):
            results.append(fut.result())

    # Preserve input order for readability.
    by_label = {label: data for label, data in results}
    return [(j["label"], by_label.get(j["label"])) for j in jobs]


def json_contract(schema_hint: str) -> str:
    return (
        "\n\nRespond with ONLY a single JSON object matching this shape "
        "(no markdown fences, no prose outside JSON):\n"
        f"{schema_hint}\n"
    )


# ---------------------------------------------------------------------------
# phase prompts (mirrors red-green-workflow.js)
# ---------------------------------------------------------------------------

def build_ctx(repo: Path, bug: str, live_repro: str, test_command: str) -> str:
    parts = [
        f"Repository root: {repo}",
        "Bug report (verbatim, plus what is already known):",
        bug,
    ]
    if live_repro:
        parts.append(f"How to run/observe the live product: {live_repro}")
    if test_command:
        parts.append(f"Known full-suite test command: {test_command}")
    return "\n".join(parts)


def rules(scripts_dir: Path, repo: Path) -> str:
    sd = str(scripts_dir)
    return f"""Red-green rules (non-negotiable):
- A red is only a red when the test FAILS with the assertion you predicted BEFORE running it. A passing test, a compile/build error, or a setup crash is NOT a red.
- Fix product code only; never edit a test to make it pass.
- Name tests after the bug, assert behavior not implementation, use the cheapest tier that can fail on this bug.
- This workflow path is always Complex: yes → validation panel uses --with-grok (Opus + GPT + Grok).
- After green: run panel, EVALUATE findings, remediate only accepted findings or material consensus gaps.
- Helpers: '{sd}/run_red.sh -p <regex> -- <cmd>', '{sd}/run_green.sh -- <cmd>',
  '{sd}/run_adversary_review.sh --workspace {repo} --context-file <f> --with-grok'."""


EVIDENCE_SCHEMA = """{
  "summary": "string",
  "facts": [{"fact": "string", "evidence": "file:line or command output"}],
  "reproducedLive": false,
  "reproSteps": "string or empty"
}"""

HYPOTHESIS_SCHEMA = """{
  "rootCause": "string",
  "mechanism": "how this cause produces every reported symptom",
  "location": "file:line or component",
  "confidence": "high|medium|low",
  "disconfirmingCheck": "concrete check that would refute this if wrong"
}"""

VERDICT_SCHEMA = """{
  "refuted": true,
  "reason": "string"
}"""

RED_SCHEMA = """{
  "isRed": true,
  "testFiles": ["path"],
  "testCommand": "exact command for just the new test(s)",
  "predictedFailure": "string",
  "observedFailure": "string",
  "mode": "test-first|surgical-revert|invariant-guard",
  "notes": "string"
}"""

FIX_SCHEMA = """{
  "filesChanged": ["path"],
  "description": "string"
}"""

GREEN_SCHEMA = """{
  "redTestPasses": true,
  "suitePasses": true,
  "suiteCommand": "string",
  "output": "string",
  "failures": "string if any"
}"""

EVAL_SCHEMA = """{
  "ok": true,
  "skillDone": true,
  "findings": ["raw panel findings"],
  "acceptedFindings": [],
  "rejectedFindings": [],
  "consensusGaps": [],
  "reworkStep": null,
  "summary": "one sentence"
}"""

REMEDIATE_SCHEMA = (
    '{\n'
    '  "reworkStep": 4,\n'
    '  "filesChanged": ["path"],\n'
    '  "description": "string",\n'
    '  "red": ' + RED_SCHEMA + ',\n'
    '  "green": ' + GREEN_SCHEMA + '\n'
    '}'
)


# ---------------------------------------------------------------------------
# phases
# ---------------------------------------------------------------------------

def phase_investigate(
    ctx: str, workspace: Path, outdir: Path, scripts_dir: Path, model: str | None, max_wait: int
) -> list[dict[str, Any]]:
    log("PHASE Investigate — 4 parallel ask agents")
    jobs = [
        {
            "label": "inv_code",
            "mode": "ask",
            "write": False,
            "prompt": f"""{ctx}

Investigate the CODE implicated by this bug. Locate components/functions on the
failing path, read them, and trace data/control flow that could produce the
symptom. Concrete facts with file:line — no speculation without a marked check.
Do NOT modify any file.
{json_contract(EVIDENCE_SCHEMA)}""",
        },
        {
            "label": "inv_history",
            "mode": "ask",
            "write": False,
            "prompt": f"""{ctx}

Investigate HISTORY (git log/blame/diff): recent changes, when the symptom
plausibly started, suspicious commits, related past fixes. Facts with commit
hashes / file:line. Do NOT modify any file.
{json_contract(EVIDENCE_SCHEMA)}""",
        },
        {
            "label": "inv_live",
            "mode": None,  # may run the product
            "write": False,
            "prompt": f"""{ctx}

Reproduce the bug LIVE if possible: run the failing invocation, capture output,
logs, exit codes, process state (hangs: stack sample). Minimize reproduction.
Check running artifact matches source. If impossible, say why and gather strongest
recorded evidence. You may run the product; do NOT modify repo source.
Set reproducedLive and reproSteps.
{json_contract(EVIDENCE_SCHEMA)}""",
        },
        {
            "label": "inv_harness",
            "mode": "ask",
            "write": False,
            "prompt": f"""{ctx}

Investigate the TEST HARNESS (README, CLAUDE.md, CI, Makefile;
`{scripts_dir}/detect_stack.sh {workspace}` can help). Report full-suite command,
single-test syntax, conventions near implicated code, existing near-miss tests,
cheapest tier that can exercise this bug. Do NOT modify any file.
{json_contract(EVIDENCE_SCHEMA)}""",
        },
    ]
    ordered = parallel_agents(jobs, workspace=workspace, outdir=outdir, model=model, max_wait=max_wait)
    evidence = [data for _, data in ordered if data]
    if not evidence:
        die("all investigators failed", 1)
    return evidence


def evidence_text(evidence: list[dict[str, Any]]) -> str:
    chunks = []
    for i, e in enumerate(evidence, 1):
        facts = e.get("facts") or []
        fact_lines = "\n".join(
            f"* {f.get('fact', '')} [{f.get('evidence', '')}]" for f in facts if isinstance(f, dict)
        )
        repro = e.get("reproSteps") or ""
        chunks.append(
            f"--- Evidence set {i} ---\n{e.get('summary', '')}\n{fact_lines}"
            + (f"\nRepro steps: {repro}" if repro else "")
        )
    return "\n\n".join(chunks)


def phase_diagnose(
    ctx: str,
    evidence: list[dict[str, Any]],
    workspace: Path,
    outdir: Path,
    model: str | None,
    max_wait: int,
) -> dict[str, Any] | None:
    log("PHASE Diagnose — adversarial hypotheses")
    ev = evidence_text(evidence)
    lenses = [
        ("recent-change", "a recent code/config/dependency change regressed previously-working behavior"),
        ("state-lifecycle", "a state machine, lifecycle, ordering, or concurrency flaw that was always latent"),
        ("environment", "environment/config/artifact mismatch: stale binary, platform difference, bad input contract, external dependency"),
    ]
    refutations: list[str] = []
    winner: dict[str, Any] | None = None

    for round_i in range(2):
        extra = ""
        if refutations:
            extra = (
                "\nPrior hypotheses were REFUTED — do not repeat them; account for them:\n"
                + "\n".join(refutations)
            )

        # Hypotheses in parallel
        hyp_jobs = [
            {
                "label": f"hyp_{key}_r{round_i}",
                "mode": "ask",
                "write": False,
                "prompt": f"""{ctx}

All gathered evidence:
{ev}
{extra}

Propose the single most plausible ROOT CAUSE through this lens: {angle}.
Read the actual code at the location you name. Mechanism must explain EVERY
reported symptom; if it cannot, lower confidence. Do NOT modify any file.
{json_contract(HYPOTHESIS_SCHEMA)}""",
                "_key": key,
            }
            for key, angle in lenses
        ]
        hyps = parallel_agents(hyp_jobs, workspace=workspace, outdir=outdir, model=model, max_wait=max_wait)

        # Refute each surviving hypothesis with 2 verifiers (parallel across all)
        refute_jobs = []
        hyp_by_label: dict[str, tuple[str, dict[str, Any]]] = {}
        for (label, hyp), job in zip(hyps, hyp_jobs):
            if not hyp:
                continue
            key = job["_key"]
            hyp_by_label[label] = (key, hyp)
            for n in (1, 2):
                refute_jobs.append(
                    {
                        "label": f"refute_{key}_r{round_i}_{n}",
                        "mode": "ask",
                        "write": False,
                        "prompt": f"""{ctx}

Evidence:
{ev}

Hypothesis under test (lens {key}): root cause "{hyp.get('rootCause')}" at {hyp.get('location')};
mechanism: {hyp.get('mechanism')}

You are adversarial verifier #{n}. Try to REFUTE it: read the code at the named
location, check the mechanism against the evidence, run/devise the disconfirming
check: {hyp.get('disconfirmingCheck') or 'devise one'}. Default to refuted=true
if the mechanism does not fully explain the symptoms. Do NOT modify any file.
{json_contract(VERDICT_SCHEMA)}""",
                        "_hyp_label": label,
                        "_key": key,
                    }
                )

        refute_results = parallel_agents(
            refute_jobs, workspace=workspace, outdir=outdir, model=model, max_wait=max_wait
        )

        # Group verdicts by hyp
        verdicts_by_hyp: dict[str, list[dict[str, Any]]] = {lbl: [] for lbl in hyp_by_label}
        for job, (label, data) in zip(refute_jobs, refute_results):
            hyp_label = job["_hyp_label"]
            if data:
                verdicts_by_hyp.setdefault(hyp_label, []).append(data)
                if data.get("refuted"):
                    key, hyp = hyp_by_label[hyp_label]
                    refutations.append(
                        f'- [{key}] "{hyp.get("rootCause")}": {data.get("reason")}'
                    )

        survivors: list[tuple[str, dict[str, Any]]] = []
        for hyp_label, (key, hyp) in hyp_by_label.items():
            vs = verdicts_by_hyp.get(hyp_label) or []
            if vs and all(not v.get("refuted") for v in vs):
                survivors.append((key, hyp))

        if survivors:
            order = {"high": 0, "medium": 1, "low": 2}
            survivors.sort(key=lambda kh: order.get(str(kh[1].get("confidence")), 3))
            key, hyp = survivors[0]
            winner = {**hyp, "lens": key}
            log(f"Diagnosis survived ({key}): {hyp.get('rootCause')}")
            break
        log(f"Diagnose round {round_i}: all hypotheses refuted")

    return winner


def phase_red(
    ctx: str,
    rules_text: str,
    diagnosis: dict[str, Any],
    ev: str,
    workspace: Path,
    outdir: Path,
    scripts_dir: Path,
    model: str | None,
    max_wait: int,
) -> dict[str, Any] | None:
    log("PHASE Red")
    feedback = ""
    red: dict[str, Any] | None = None
    for attempt in range(3):
        red = run_agent(
            label=f"red_write_{attempt}",
            prompt=f"""{ctx}

Diagnosed root cause: {diagnosis.get('rootCause')} at {diagnosis.get('location')}.
Mechanism: {diagnosis.get('mechanism')}

Harness / evidence:
{ev}

{rules_text}

Write the RED regression test for this bug at the cheapest sufficient tier.
(1) assert CORRECT behavior; (2) state predicted failure BEFORE running;
(3) run and confirm that exact assertion fails.
Use `{scripts_dir}/run_red.sh -p <regex> -- <cmd>` when possible.
Do NOT write the fix. Do NOT weaken the assertion.
{feedback}
{json_contract(RED_SCHEMA)}""",
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode=None,
            write=True,
            max_wait=max_wait,
        )
        if not red:
            continue
        if red.get("mode") == "surgical-revert":
            return red
        check = run_agent(
            label=f"red_verify_{attempt}",
            prompt=f"""{ctx}

{rules_text}

A red test was added: files {json.dumps(red.get('testFiles'))}, command: {red.get('testCommand')}
Predicted: {red.get('predictedFailure')}
Claimed observed: {red.get('observedFailure')}

Adversarially verify: re-run via `{scripts_dir}/run_red.sh -p <regex> -- {red.get('testCommand')}`
and confirm (a) it fails, (b) failure is the predicted assertion (not compile/setup),
(c) the test encodes the diagnosed bug and asserts behavior. refuted=true if any check fails.
Do NOT modify any file.
{json_contract(VERDICT_SCHEMA)}""",
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode="ask",
            write=False,
            max_wait=max_wait,
        )
        if check and check.get("refuted"):
            feedback = f"\nPrevious attempt rejected: {check.get('reason')}\nAddress that."
            red["isRed"] = False
            log(f"Red rejected: {check.get('reason')}")
            continue
        if check:
            red["isRed"] = True
            return red
    return red if red and (red.get("isRed") or red.get("mode") == "surgical-revert") else None


def phase_fix(
    ctx: str,
    rules_text: str,
    diagnosis: dict[str, Any],
    red: dict[str, Any],
    workspace: Path,
    outdir: Path,
    model: str | None,
    max_wait: int,
) -> dict[str, Any] | None:
    log("PHASE Fix")
    surgical = ""
    if red.get("mode") == "surgical-revert":
        surgical = (
            "\nThis is surgical-revert mode: after fixing and going green, verify the red by "
            "surgically reverting the BEHAVIOR (keep compiling), predict failure, run, match, "
            "restore, re-green. Record predicted vs observed in description."
        )
    return run_agent(
        label="fix",
        prompt=f"""{ctx}

Diagnosed root cause: {diagnosis.get('rootCause')} at {diagnosis.get('location')}.
Mechanism: {diagnosis.get('mechanism')}
Red test: files {json.dumps(red.get('testFiles'))}, command: {red.get('testCommand')}, mode: {red.get('mode')}

{rules_text}

Implement the MINIMAL fix for the root cause. Product code only — do not touch
the test files. Match surrounding style.{surgical}
{json_contract(FIX_SCHEMA)}""",
        workspace=workspace,
        outdir=outdir,
        model=model,
        mode=None,
        write=True,
        max_wait=max_wait,
    )


def phase_green(
    ctx: str,
    rules_text: str,
    diagnosis: dict[str, Any],
    red: dict[str, Any],
    fix: dict[str, Any],
    workspace: Path,
    outdir: Path,
    scripts_dir: Path,
    test_command: str,
    model: str | None,
    max_wait: int,
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    log("PHASE Green")
    green: dict[str, Any] | None = None
    current_fix = fix
    for attempt in range(3):
        green = run_agent(
            label=f"green_{attempt}",
            prompt=f"""{ctx}

A fix for "{diagnosis.get('rootCause')}" changed: {json.dumps(current_fix.get('filesChanged'))}.
Regression test: {red.get('testCommand')}

Verify GREEN:
(1) `{scripts_dir}/run_green.sh -- {red.get('testCommand')}` must pass
(2) full suite for affected module ({test_command or 'discover from Makefile/CI/README'}) must pass
Report exact commands/results. Do NOT modify any file.
{json_contract(GREEN_SCHEMA)}""",
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode="ask",
            write=False,
            max_wait=max_wait,
        )
        if green and green.get("redTestPasses") and green.get("suitePasses"):
            return green, current_fix
        if attempt == 2:
            break
        log(f"Not green yet: {(green or {}).get('failures') or 'runner failed'} — repairing")
        repaired = run_agent(
            label=f"fix_repair_{attempt}",
            prompt=f"""{ctx}

Root cause: {diagnosis.get('rootCause')}. Fix so far: {json.dumps(current_fix.get('filesChanged'))}.
Green failed:
{(green or {}).get('output') or '(no output)'}
Failures: {(green or {}).get('failures') or ''}

{rules_text}

Repair the FIX (product code only — never the tests) so regression + suite pass.
{json_contract(FIX_SCHEMA)}""",
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode=None,
            write=True,
            max_wait=max_wait,
        )
        if repaired:
            current_fix = {
                "filesChanged": sorted(
                    set((current_fix.get("filesChanged") or []) + (repaired.get("filesChanged") or []))
                ),
                "description": f"{current_fix.get('description', '')}\n[repair] {repaired.get('description', '')}".strip(),
            }
    return green, current_fix


def write_worksheet(
    path: Path,
    *,
    bug: str,
    diagnosis: dict[str, Any],
    red: dict[str, Any],
    fix: dict[str, Any],
    green: dict[str, Any],
    live: bool,
    live_steps: str,
) -> None:
    path.write_text(
        f"""# Bug worksheet (CLI workflow)

**Complex?:** yes — reason: Cursor CLI multi-agent workflow path

## 1. Reproduction
> {bug}

## 2. Live reproduction
- Reproduced live: {live}
- Steps: {live_steps or '(see evidence)'}

## 3. Root cause
`{diagnosis.get('location')}` — {diagnosis.get('rootCause')}
Mechanism: {diagnosis.get('mechanism')}
Lens: {diagnosis.get('lens')}

## 4. Red
- Files: {json.dumps(red.get('testFiles'))}
- Command: {red.get('testCommand')}
- Predicted: {red.get('predictedFailure')}
- Observed: {red.get('observedFailure')}
- Mode: {red.get('mode')}

## 5. Fix
{fix.get('description')}
Files: {json.dumps(fix.get('filesChanged'))}

## 6. Green
- redTestPasses: {green.get('redTestPasses')}
- suitePasses: {green.get('suitePasses')}
- suiteCommand: {green.get('suiteCommand')}
- output: {green.get('output')}
""",
        encoding="utf-8",
    )


def phase_validation(
    ctx: str,
    rules_text: str,
    bug: str,
    workspace: Path,
    outdir: Path,
    scripts_dir: Path,
    worksheet: Path,
    diagnosis: dict[str, Any],
    red: dict[str, Any],
    fix: dict[str, Any],
    green: dict[str, Any],
    model: str | None,
    max_wait: int,
) -> dict[str, Any]:
    log("PHASE Validation panel + evaluate + remediate")
    remediation_log: list[dict[str, Any]] = []
    last_eval: dict[str, Any] = {
        "ok": False,
        "skillDone": False,
        "findings": [],
        "acceptedFindings": [],
        "consensusGaps": [],
        "notes": "",
    }

    for round_i in range(1, 4):
        panel_outdir = outdir / f"panel_r{round_i}"
        panel_outdir.mkdir(parents=True, exist_ok=True)
        panel_script = scripts_dir / "run_adversary_review.sh"
        cp = run_cmd(
            [
                str(panel_script),
                "--workspace",
                str(workspace),
                "--context-file",
                str(worksheet),
                "--bug-file",
                str(worksheet),
                "--with-grok",
                "--outdir",
                str(panel_outdir),
            ],
            timeout=max_wait + 60,
        )
        if cp.returncode == 3:
            log("Validation panel skipped (CLI gate)")
            return {
                "ok": True,
                "skillDone": True,
                "findings": [],
                "acceptedFindings": [],
                "consensusGaps": [],
                "notes": "skipped-cli-gate",
                "rounds": 0,
                "remediationLog": [],
            }

        aggregate_path = panel_outdir / "AGGREGATE.json"
        aggregate_text = aggregate_path.read_text(encoding="utf-8") if aggregate_path.is_file() else "{}"

        evaluation = run_agent(
            label=f"eval_r{round_i}",
            prompt=f"""{ctx}

{rules_text}

You are the facilitator evaluating a red-green validation panel (Complex: yes, Grok on).

Worksheet path: {worksheet}
AGGREGATE.json:
{aggregate_text[:12000]}

Current work:
- Diagnosis: {diagnosis.get('rootCause')} at {diagnosis.get('location')}
- Red: {red.get('testCommand')} / predicted={red.get('predictedFailure')}
- Fix: {json.dumps(fix.get('filesChanged'))} — {fix.get('description')}
- Green: red={green.get('redTestPasses')} suite={green.get('suitePasses')}

Dedupe findings. For each: accept / reject / needs-evidence.
Reject MUST cite path/hunk/command. Nits alone are not material.
Material consensus gap = ok_split OR reworkStep_split on accepted/needs-evidence.

Set:
- ok = raw panel pass (all panelists ok=true)
- skillDone = ok AND acceptedFindings empty AND consensusGaps empty
- reworkStep = earliest 1-5 among accepted/gaps, or null if skillDone
Do NOT modify repo files.
{json_contract(EVAL_SCHEMA)}""",
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode="ask",
            write=False,
            max_wait=max_wait,
        )
        if not evaluation:
            last_eval = {
                "ok": False,
                "skillDone": False,
                "findings": ["evaluation agent failed"],
                "acceptedFindings": [],
                "consensusGaps": [],
                "rounds": round_i,
                "aggregatePath": str(aggregate_path),
                "remediationLog": remediation_log,
            }
            continue

        evaluation["rounds"] = round_i
        evaluation["aggregatePath"] = str(aggregate_path)
        evaluation["remediationLog"] = remediation_log
        last_eval = evaluation

        if evaluation.get("skillDone"):
            log(f"Validation skill-done on round {round_i}")
            return evaluation

        step = evaluation.get("reworkStep") or 4
        accepted = evaluation.get("acceptedFindings") or []
        gaps = evaluation.get("consensusGaps") or []
        log(f"Remediation round {round_i}: step={step} accepted={accepted} gaps={gaps}")

        rem = run_agent(
            label=f"remediate_r{round_i}",
            prompt=f"""{ctx}

{rules_text}

Validation evaluation requires remediations (round {round_i}).
reworkStep={step} (1=repro 2=live 3=red 4=fix 5=green).
Accepted findings:
{chr(10).join(f'- {a}' for a in accepted) or '(none)'}
Material consensus gaps:
{chr(10).join(f'- {g}' for g in gaps) or '(none)'}

Current diagnosis: {diagnosis.get('rootCause')} at {diagnosis.get('location')}
Current red: {json.dumps(red.get('testFiles'))} / {red.get('testCommand')}
Current fix: {json.dumps(fix.get('filesChanged'))}

Investigate accepted findings / gaps only. Return to step {step} and redo FORWARD
through green. Product code only when fixing; never weaken the red test.
Use `{scripts_dir}/run_red.sh` / `run_green.sh` as appropriate.
{json_contract(REMEDIATE_SCHEMA)}""",
            workspace=workspace,
            outdir=outdir,
            model=model,
            mode=None,
            write=True,
            max_wait=max_wait,
        )
        if rem:
            remediation_log.append(
                {
                    "round": round_i,
                    "reworkStep": rem.get("reworkStep"),
                    "description": rem.get("description"),
                    "filesChanged": rem.get("filesChanged"),
                    "acceptedFindings": accepted,
                    "consensusGaps": gaps,
                }
            )
            if rem.get("filesChanged"):
                fix["filesChanged"] = sorted(
                    set((fix.get("filesChanged") or []) + (rem.get("filesChanged") or []))
                )
                fix["description"] = (
                    f"{fix.get('description', '')}\n[remediation r{round_i}] {rem.get('description', '')}"
                ).strip()
            if rem.get("red") and (rem.get("reworkStep") or 99) <= 3:
                red.update(rem["red"])
            if rem.get("green"):
                green.update(rem["green"])
            write_worksheet(
                worksheet,
                bug=bug,
                diagnosis=diagnosis,
                red=red,
                fix=fix,
                green=green,
                live=True,
                live_steps="",
            )

    last_eval["remediationLog"] = remediation_log
    return last_eval


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--workspace", required=True, help="absolute repo root")
    p.add_argument("--bug", default="", help="verbatim symptom + known context")
    p.add_argument("--bug-file", default="", help="path to bug text file")
    p.add_argument("--test-command", default="", help="full-suite command if known")
    p.add_argument("--live-repro", default="", help="how to run/observe the product")
    p.add_argument("--scripts-dir", default=str(SCRIPT_DIR), help="red-green scripts dir")
    p.add_argument("--outdir", default="", help="artifact directory")
    p.add_argument("--model", default=os.environ.get("RED_GREEN_WORKFLOW_MODEL", ""), help="agent model id")
    p.add_argument("--max-wait-secs", type=int, default=int(os.environ.get("RED_GREEN_WORKFLOW_MAX_WAIT", DEFAULT_MAX_WAIT)))
    p.add_argument("--dry-run", action="store_true", help="print plan only")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    workspace = Path(args.workspace).resolve()
    if not workspace.is_dir():
        die(f"workspace is not a directory: {workspace}", 64)

    bug = args.bug
    if args.bug_file:
        bug = Path(args.bug_file).read_text(encoding="utf-8")
    if not bug.strip():
        die("--bug or --bug-file is required", 64)

    scripts_dir = Path(args.scripts_dir).resolve()
    outdir = Path(args.outdir) if args.outdir else Path(tempfile.mkdtemp(prefix="rg-workflow-cli."))
    outdir.mkdir(parents=True, exist_ok=True)
    model = args.model or None
    max_wait = args.max_wait_secs

    log(f"outdir: {outdir}")
    log(f"workspace: {workspace}")
    log("Complex: yes (CLI workflow always uses --with-grok for the panel)")

    if args.dry_run:
        print(json.dumps({
            "workspace": str(workspace),
            "scriptsDir": str(scripts_dir),
            "outdir": str(outdir),
            "model": model,
            "phases": ["Investigate", "Diagnose", "Red", "Fix", "Green", "ValidationPanel"],
        }, indent=2))
        return 0

    check_agent_cli(scripts_dir)

    ctx = build_ctx(workspace, bug.strip(), args.live_repro, args.test_command)
    rules_text = rules(scripts_dir, workspace)

    # 1 Investigate
    evidence = phase_investigate(ctx, workspace, outdir, scripts_dir, model, max_wait)
    live = next((e for e in evidence if e.get("reproducedLive")), None)
    ev = evidence_text(evidence)
    (outdir / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")

    # 2 Diagnose
    diagnosis = phase_diagnose(ctx, evidence, workspace, outdir, model, max_wait)
    if not diagnosis:
        report = {
            "status": "undiagnosed",
            "message": "No root-cause hypothesis survived adversarial verification.",
            "outdir": str(outdir),
        }
        (outdir / "REPORT.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 1
    (outdir / "diagnosis.json").write_text(json.dumps(diagnosis, indent=2) + "\n", encoding="utf-8")

    # 3 Red
    red = phase_red(ctx, rules_text, diagnosis, ev, workspace, outdir, scripts_dir, model, max_wait)
    if not red or (not red.get("isRed") and red.get("mode") != "surgical-revert"):
        report = {
            "status": "no-red",
            "message": "Could not produce a verified failing test.",
            "diagnosis": diagnosis,
            "outdir": str(outdir),
        }
        (outdir / "REPORT.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 1

    # 4 Fix
    fix = phase_fix(ctx, rules_text, diagnosis, red, workspace, outdir, model, max_wait)
    if not fix:
        report = {"status": "fix-failed", "diagnosis": diagnosis, "red": red, "outdir": str(outdir)}
        (outdir / "REPORT.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 1

    # 5 Green
    green, fix = phase_green(
        ctx, rules_text, diagnosis, red, fix, workspace, outdir, scripts_dir,
        args.test_command, model, max_wait,
    )
    if not (green and green.get("redTestPasses") and green.get("suitePasses")):
        report = {
            "status": "red-fix-not-green",
            "diagnosis": diagnosis,
            "red": red,
            "fix": fix,
            "green": green,
            "outdir": str(outdir),
            "caveats": ["Green verification did not fully pass — skipped validation panel."],
        }
        (outdir / "REPORT.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 1

    worksheet = outdir / "worksheet.md"
    write_worksheet(
        worksheet,
        bug=bug.strip(),
        diagnosis=diagnosis,
        red=red,
        fix=fix,
        green=green,
        live=bool(live),
        live_steps=(live or {}).get("reproSteps") or "",
    )

    # 6–8 Validation
    adversary = phase_validation(
        ctx, rules_text, bug.strip(), workspace, outdir, scripts_dir, worksheet,
        diagnosis, red, fix, green, model, max_wait,
    )

    skipped = "skipped-cli-gate" in str(adversary.get("notes") or "")
    skill_done = bool(adversary.get("skillDone"))
    report = {
        "status": "green-adversary-skipped" if skipped else ("green" if skill_done else "adversary-rejected"),
        "complex": True,
        "reproduction": {
            "live": bool(live),
            "steps": (live or {}).get("reproSteps") or "(not reproduced live — see evidence)",
        },
        "diagnosis": diagnosis,
        "red": red,
        "fix": fix,
        "green": green,
        "adversary": adversary,
        "outdir": str(outdir),
        "caveats": (
            [f"Validation panel skipped: {adversary.get('notes')}"]
            if skipped
            else (
                []
                if skill_done
                else [
                    "Validation panel did not reach skill-done — do not present as verified.",
                    *(adversary.get("acceptedFindings") or []),
                    *(adversary.get("consensusGaps") or []),
                ]
            )
        ),
    }
    (outdir / "REPORT.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if (skill_done or skipped) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        die("interrupted", 2)
