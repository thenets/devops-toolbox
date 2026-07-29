#!/usr/bin/env bash
# run_adversary_review.sh — multi-model validation panel via Cursor `agent` CLI.
#
# Runs the latest available Opus and GPT models (resolved dynamically) in
# read-only ask mode against the completed red-green work. Optionally adds
# Grok when the bug is complex (--with-grok / RED_GREEN_WITH_GROK=1).
# Every panelist must verdict ok=true for raw pass. Facilitator must still
# evaluate (skill step 7) and may remediate on accepted findings / consensus gaps.
#
# Usage:
#   run_adversary_review.sh --workspace <repo> \
#     [--bug-file <path>] [--context-file <path>] \
#     [--outdir <dir>] [--max-wait-secs N] \
#     [--with-grok] \
#     [--opus-model ID] [--gpt-model ID] [--grok-model ID]
#
# Context file should describe: reproduction, complex?, live repro, red test +
# predicted vs observed failure, fix files/mechanism, green commands + results.
#
# Exit codes:
#   0  all panelists ok (raw pass) — still run skill evaluation step 7
#   1  one or more rejected (rework may be required) — see AGGREGATE.json
#   2  runner/infra failure (model resolve failed, bad JSON, agent crash)
#   3  skipped — agent CLI missing or not authenticated (do NOT enter step 8)
#   64 usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

workspace=""
bug_file=""
context_file=""
outdir=""
opus_override=""
gpt_override=""
grok_override=""
with_grok=0
max_wait_secs=900

if [ "${RED_GREEN_WITH_GROK:-0}" = "1" ]; then
  with_grok=1
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) workspace="${2:-}"; shift 2 ;;
    --bug-file) bug_file="${2:-}"; shift 2 ;;
    --context-file) context_file="${2:-}"; shift 2 ;;
    --outdir) outdir="${2:-}"; shift 2 ;;
    --opus-model) opus_override="${2:-}"; shift 2 ;;
    --gpt-model) gpt_override="${2:-}"; shift 2 ;;
    --grok-model) grok_override="${2:-}"; shift 2 ;;
    --with-grok) with_grok=1; shift ;;
    --max-wait-secs) max_wait_secs="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | tr -d '#'
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 64
      ;;
  esac
done

if [ -z "$workspace" ]; then
  echo "usage: run_adversary_review.sh --workspace <repo> [--context-file f] [--bug-file f] [--with-grok]" >&2
  exit 64
fi
if [ ! -d "$workspace" ]; then
  echo "workspace is not a directory: $workspace" >&2
  exit 64
fi

# Gate: only run when Cursor agent CLI is present + authenticated.
# Exit 3 = skipped (not a rejection) — callers must not enter step-8 remediation.
set +e
gate_out="$("$SCRIPT_DIR/check_agent_cli.sh" 2>&1)"
gate_ec=$?
set -e
if [ "$gate_ec" -ne 0 ]; then
  echo "$gate_out" >&2
  echo "VALIDATION PANEL SKIPPED: Cursor agent CLI missing or not authenticated (check_agent_cli exit $gate_ec)." >&2
  echo "Do not run step 8 (remediation loop). Proceed with steps 1–5 only; note the skip in the report." >&2
  exit 3
fi
echo ">>> $gate_out"

if [ -n "$opus_override" ]; then export RED_GREEN_OPUS_MODEL="$opus_override"; fi
if [ -n "$gpt_override" ]; then export RED_GREEN_GPT_MODEL="$gpt_override"; fi
if [ -n "$grok_override" ]; then export RED_GREEN_GROK_MODEL="$grok_override"; fi
if [ "$with_grok" -eq 1 ]; then
  export RED_GREEN_REQUIRE_GROK=1
fi

# shellcheck disable=SC1090
eval "$("$SCRIPT_DIR/resolve_review_models.sh")"
if [ "$with_grok" -eq 1 ]; then
  echo ">>> Validation panel models: opus=$OPUS_MODEL  gpt=$GPT_MODEL  grok=$GROK_MODEL"
else
  echo ">>> Validation panel models: opus=$OPUS_MODEL  gpt=$GPT_MODEL  (grok off)"
fi

[ -n "$outdir" ] || outdir="$(mktemp -d "${TMPDIR:-/tmp}/rg-adversary.XXXXXX")"
mkdir -p "$outdir"
echo ">>> Validation panel outdir: $outdir"

bug_text=""
if [ -n "$bug_file" ] && [ -f "$bug_file" ]; then
  bug_text="$(cat "$bug_file")"
fi
context_text=""
if [ -n "$context_file" ] && [ -f "$context_file" ]; then
  context_text="$(cat "$context_file")"
else
  context_text="(no context file — inspect the workspace git diff / recent changes and infer the red-green work)"
fi

PROMPT_FILE="$outdir/prompt.txt"
cat >"$PROMPT_FILE" <<EOF
You are an ADVERSARIAL reviewer of a red-green bug fix. Your job is to try to
REFUTE the claim that this fix is correct and complete. Default to skepticism.

Read-only: do NOT modify any files. You may run read-only commands (git show,
git diff, cat, test runners in dry observation only if needed to verify claims).

Bug report / symptom:
${bug_text:-"(not provided as a file)"}

Red-green worksheet / claimed work:
${context_text}

Review checklist (every item that fails is a finding):
1. Reproduction — is the one-sentence input→wrong-output concrete and believable?
2. Live repro — was the bug observed in a running product/artifact when feasible?
3. Red test — asserts CORRECT behavior; named after the bug; cheapest sufficient tier;
   predicted failure matched observed failure; NOT a compile/setup crash.
4. Fix — product code only; addresses root cause (not symptom mask); minimal; no
   silent weakening of the red test.
5. Green — red test and affected suite actually pass; claims match evidence.
6. Loop honesty — any skipped gate must be explicitly justified.

Respond with ONLY a single JSON object (no markdown fences, no prose outside JSON):
{
  "ok": boolean,
  "findings": ["concrete problem 1", "..."],
  "reworkStep": null or 1 or 2 or 3 or 4 or 5,
  "reworkReason": "why that step, or empty if ok",
  "summary": "one sentence verdict"
}

reworkStep meanings (pick the EARLIEST step that must be redone):
  1 = reproduce the behavior
  2 = live environment reproduction
  3 = create/fix the red test
  4 = fix the bug (product code)
  5 = re-check green
Set ok=true only when findings is empty and reworkStep is null.
EOF

extract_json() {
  # Prefer a fenced json block; else first {...} object in the text.
  local raw="$1"
  local extracted
  extracted="$(printf '%s' "$raw" | awk '
    BEGIN { inblock=0 }
    /^```json/ { inblock=1; next }
    /^```/ && inblock { exit }
    inblock { print; next }
  ')"
  if [ -z "$extracted" ]; then
    extracted="$(printf '%s' "$raw" | awk '
      /\{/ { start=1 }
      start { buf = buf $0 "\n" }
      END { print buf }
    ')"
  fi
  # Keep from first { to last }
  printf '%s' "$extracted" | awk '
    BEGIN { s=-1 }
    {
      line=$0
      for (i=1; i<=length(line); i++) {
        c=substr(line,i,1)
        if (c=="{" && s<0) s=length(out)+1
        if (s>=0) out=out c
        if (c=="}") last=length(out)
      }
      if (s>=0) out=out "\n"
    }
    END { if (s>=0 && last>0) print substr(out,1,last) }
  '
}

run_one() {
  local label="$1" model="$2"
  local raw_file="$outdir/${label}.raw.json"
  local verdict_file="$outdir/${label}.verdict.json"
  local log_file="$outdir/${label}.log"

  echo ">>> Starting panelist:$label model=$model"

  # --mode ask: read-only review. --trust: non-interactive workspace trust for -p.
  # --sandbox disabled: reviewers may need to run read-only git/test inspection.
  set +e
  agent -p \
    --mode ask \
    --model "$model" \
    --workspace "$workspace" \
    --trust \
    --sandbox disabled \
    --output-format json \
    "$(cat "$PROMPT_FILE")" \
    >"$raw_file" 2>"$log_file"
  local ac=$?
  set -e

  if [ "$ac" -ne 0 ]; then
    echo "{\"ok\":false,\"findings\":[\"agent CLI exited $ac for $label\"],\"reworkStep\":5,\"reworkReason\":\"adversary runner failed — inspect $log_file\",\"summary\":\"infra failure for $label\",\"model\":\"$model\",\"runnerExit\":$ac}" >"$verdict_file"
    echo ">>> panelist:$label FAILED (agent exit $ac)"
    return 0
  fi

  local result_text
  if command -v jq >/dev/null 2>&1; then
    result_text="$(jq -r '.result // empty' "$raw_file" 2>/dev/null || true)"
  else
    result_text="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result",""))' "$raw_file" 2>/dev/null || true)"
  fi

  local verdict
  verdict="$(extract_json "$result_text")"
  if [ -z "$verdict" ]; then
    echo "{\"ok\":false,\"findings\":[\"could not parse JSON verdict from $label\"],\"reworkStep\":5,\"reworkReason\":\"unparseable adversary output\",\"summary\":\"parse failure for $label\",\"model\":\"$model\",\"rawResult\":$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:2000]))' <<<"$result_text")}" >"$verdict_file"
    echo ">>> panelist:$label parse failure"
    return 0
  fi

  # Attach model id for the aggregate.
  if command -v jq >/dev/null 2>&1; then
    jq --arg m "$model" --arg l "$label" '. + {model:$m, label:$l}' <<<"$verdict" >"$verdict_file" 2>/dev/null \
      || printf '%s\n' "$verdict" >"$verdict_file"
  else
    printf '%s\n' "$verdict" >"$verdict_file"
  fi
  echo ">>> panelist:$label done → $verdict_file"
}

# Parallel reviews.
run_one opus "$OPUS_MODEL" &
pid_opus=$!
run_one gpt "$GPT_MODEL" &
pid_gpt=$!
pid_grok=""
if [ "$with_grok" -eq 1 ]; then
  run_one grok "$GROK_MODEL" &
  pid_grok=$!
fi

wait_with_timeout() {
  local pid="$1" label="$2"
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$max_wait_secs" ]; then
      echo ">>> panelist:$label timed out after ${max_wait_secs}s — killing" >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  wait "$pid"
  return $?
}

set +e
wait_with_timeout "$pid_opus" opus
ec_opus=$?
wait_with_timeout "$pid_gpt" gpt
ec_gpt=$?
ec_grok=0
if [ -n "$pid_grok" ]; then
  wait_with_timeout "$pid_grok" grok
  ec_grok=$?
fi
set -e

aggregate="$outdir/AGGREGATE.json"
python3 - "$outdir" "$OPUS_MODEL" "$GPT_MODEL" "${GROK_MODEL:-}" "$with_grok" "$aggregate" <<'PY'
import json, sys, os
outdir, opus_m, gpt_m, grok_m, with_grok_s, out = sys.argv[1:7]
with_grok = with_grok_s in ("1", "true", "True")

def load(label, default_model):
    path = os.path.join(outdir, f"{label}.verdict.json")
    if not os.path.exists(path):
        return {
            "ok": False,
            "findings": [f"missing verdict file for {label}"],
            "reworkStep": 5,
            "reworkReason": "panelist did not produce a verdict",
            "summary": f"missing {label}",
            "model": default_model,
            "label": label,
        }
    with open(path) as f:
        data = json.load(f)
    data.setdefault("label", label)
    data.setdefault("model", default_model)
    return data

def step_of(v):
    s = v.get("reworkStep")
    return s if isinstance(s, int) and 1 <= s <= 5 else None

opus = load("opus", opus_m)
gpt = load("gpt", gpt_m)
panelists = [opus, gpt]
panel = ["opus", "gpt"]
if with_grok:
    grok = load("grok", grok_m)
    panelists.append(grok)
    panel.append("grok")
else:
    grok = None

findings = []
for v in panelists:
    for f in v.get("findings") or []:
        findings.append(f"[{v.get('label','?')}/{v.get('model','?')}] {f}")

steps_by_label = {v.get("label"): step_of(v) for v in panelists}
steps = [s for s in steps_by_label.values() if s is not None]
rework = min(steps) if steps else None

oks = [bool(v.get("ok")) for v in panelists]
ok_agree = len(set(oks)) <= 1
ok_split = not ok_agree
ok = all(oks) and not findings and rework is None

# Distinct non-null reworkSteps across panelists that rejected / pointed a step
distinct_steps = sorted({s for s in steps_by_label.values() if s is not None})
rework_step_split = len(distinct_steps) > 1

consensus = {
    "ok_agree": ok_agree,
    "ok_split": ok_split,
    "reworkStep_by_label": steps_by_label,
    "earliest": rework,
    "reworkStep_split": rework_step_split,
    "distinct_reworkSteps": distinct_steps,
}

models = {"opus": opus_m, "gpt": gpt_m}
if with_grok:
    models["grok"] = grok_m

agg = {
    "ok": ok,
    "reworkStep": rework,
    "findings": findings,
    "panel": panel,
    "withGrok": with_grok,
    "consensus": consensus,
    "opus": opus,
    "gpt": gpt,
    "models": models,
    "outdir": outdir,
}
if with_grok:
    agg["grok"] = grok

with open(out, "w") as f:
    json.dump(agg, f, indent=2)
    f.write("\n")
print(json.dumps(agg, indent=2))
PY

echo ">>> Aggregate written: $aggregate"

if command -v jq >/dev/null 2>&1; then
  ok="$(jq -r '.ok' "$aggregate")"
  rework="$(jq -r '.reworkStep // empty' "$aggregate")"
  panel="$(jq -r '.panel | join("+")' "$aggregate")"
  ok_split="$(jq -r '.consensus.ok_split' "$aggregate")"
else
  ok="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ok"])' "$aggregate")"
  rework="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("reworkStep") or "")' "$aggregate")"
  panel="$(python3 -c 'import json,sys; print("+".join(json.load(open(sys.argv[1])).get("panel") or []))' "$aggregate")"
  ok_split="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("consensus",{}).get("ok_split"))' "$aggregate")"
fi

if [ "$ok" = "True" ] || [ "$ok" = "true" ]; then
  echo "VALIDATION PANEL RAW PASS ($panel). Still run skill evaluation (step 7)."
  exit 0
fi

echo "VALIDATION PANEL RAW FAIL — reworkStep=${rework:-unknown} ok_split=${ok_split}. Inspect $aggregate" >&2
echo "Run skill evaluation (step 7). Remediate (step 8) only on accepted findings or material consensus gaps — not nits alone." >&2
exit 1
