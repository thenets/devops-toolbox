#!/usr/bin/env bash
# resolve_review_models.sh — pick strongest Opus + GPT (+ optional Grok) for
# the red-green validation panel.
#
# Prints:
#   OPUS_MODEL=<id>
#   GPT_MODEL=<id>
#   GROK_MODEL=<id>          # empty unless resolved / overridden; required
#                            # only when RED_GREEN_REQUIRE_GROK=1
#
# Override with env:
#   RED_GREEN_OPUS_MODEL, RED_GREEN_GPT_MODEL, RED_GREEN_GROK_MODEL
# Set RED_GREEN_REQUIRE_GROK=1 when --with-grok was requested (fail if missing).
# Requires: agent CLI on PATH (Cursor Agent), unless all needed overrides set.
set -euo pipefail

require_grok="${RED_GREEN_REQUIRE_GROK:-0}"

need_catalog=0
if [ -z "${RED_GREEN_OPUS_MODEL:-}" ] || [ -z "${RED_GREEN_GPT_MODEL:-}" ]; then
  need_catalog=1
fi
if [ "$require_grok" = "1" ] && [ -z "${RED_GREEN_GROK_MODEL:-}" ]; then
  need_catalog=1
fi
# Always try to resolve Grok when catalog is loaded (handy for AGGREGATE),
# but only fail if require_grok=1.
if [ -z "${RED_GREEN_GROK_MODEL:-}" ]; then
  need_catalog=1
fi

ALL_IDS=()
if [ "$need_catalog" -eq 1 ]; then
  if ! command -v agent >/dev/null 2>&1; then
    echo "resolve_review_models.sh: 'agent' CLI not found on PATH" >&2
    exit 1
  fi

  models_out="$(agent models 2>/dev/null || agent --list-models 2>/dev/null || true)"
  if [ -z "$models_out" ]; then
    echo "resolve_review_models.sh: could not list models via 'agent models'" >&2
    exit 1
  fi

  # IDs are the first whitespace-separated token on each catalog line.
  mapfile -t ALL_IDS < <(printf '%s\n' "$models_out" | awk '/^[a-zA-Z0-9._-]+ / { print $1 }')
fi

pick_best() {
  # stdin: candidate ids, one per line. stdout: best id or empty.
  # Ranking prefers higher major.minor, then higher effort tier, then thinking, and skips *-fast.
  awk '
    function verkey(id,   m, a, b) {
      if (match(id, /([0-9]+)\.([0-9]+)/, m)) return m[1]*1000 + m[2]
      if (match(id, /([0-9]+)/, m)) return m[1]*1000
      return 0
    }
    function effort(id) {
      if (id ~ /(^|-)(max|xhigh)(-|$)/) return 50
      if (id ~ /(^|-)high(-|$)/) return 40
      if (id ~ /(^|-)medium(-|$)/) return 30
      if (id ~ /(^|-)low(-|$)/) return 20
      if (id ~ /(^|-)none(-|$)/) return 10
      return 35
    }
    function thinking(id) { return (id ~ /thinking/) ? 1 : 0 }
    function skip(id) {
      return (id ~ /-fast$/ || id ~ /-fast-/ || id ~ /(^|-)(mini|nano)(-|$)/)
    }
    {
      id = $0
      if (id == "" || skip(id)) next
      score = verkey(id)*10000 + effort(id)*10 + thinking(id)
      if (score > best) { best = score; pick = id }
    }
    END { if (pick != "") print pick }
  '
}

if [ -n "${RED_GREEN_OPUS_MODEL:-}" ] && [ -n "${RED_GREEN_GPT_MODEL:-}" ]; then
  OPUS="$RED_GREEN_OPUS_MODEL"
  GPT="$RED_GREEN_GPT_MODEL"
else
  OPUS="$(printf '%s\n' "${ALL_IDS[@]}" | grep -E 'opus' | pick_best || true)"
  # Prefer flagship GPT (gpt-5.x), not Codex/Mini/Nano variants.
  GPT="$(printf '%s\n' "${ALL_IDS[@]}" | grep -E '^gpt-[0-9]' | grep -Ev 'codex|mini|nano' | pick_best || true)"

  # Fallbacks if filters were too strict.
  if [ -z "$OPUS" ]; then
    OPUS="$(printf '%s\n' "${ALL_IDS[@]}" | grep -Ei 'claude.*opus|opus' | pick_best || true)"
  fi
  if [ -z "$GPT" ]; then
    GPT="$(printf '%s\n' "${ALL_IDS[@]}" | grep -E '^gpt-' | pick_best || true)"
  fi

  OPUS="${RED_GREEN_OPUS_MODEL:-$OPUS}"
  GPT="${RED_GREEN_GPT_MODEL:-$GPT}"

  if [ -z "$OPUS" ] || [ -z "$GPT" ]; then
    echo "resolve_review_models.sh: failed to resolve models (opus='$OPUS' gpt='$GPT')" >&2
    echo "Available IDs:" >&2
    printf '  %s\n' "${ALL_IDS[@]}" >&2
    exit 1
  fi
fi

GROK="${RED_GREEN_GROK_MODEL:-}"
if [ -z "$GROK" ] && [ "${#ALL_IDS[@]}" -gt 0 ]; then
  # Prefer cursor-grok-* / grok-* flagship; pick_best skips *-fast.
  GROK="$(printf '%s\n' "${ALL_IDS[@]}" | grep -Ei 'grok' | pick_best || true)"
fi

if [ "$require_grok" = "1" ] && [ -z "$GROK" ]; then
  echo "resolve_review_models.sh: failed to resolve Grok model (required for --with-grok)" >&2
  echo "Available IDs:" >&2
  printf '  %s\n' "${ALL_IDS[@]}" >&2
  exit 1
fi

echo "OPUS_MODEL=${OPUS}"
echo "GPT_MODEL=${GPT}"
echo "GROK_MODEL=${GROK}"
