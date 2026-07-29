#!/usr/bin/env bash
# check_agent_cli.sh — gate for dual adversary review + remediation (steps 6–7).
#
# Exit codes:
#   0  Cursor `agent` CLI is on PATH and authenticated
#   1  `agent` not on PATH
#   2  `agent` present but not authenticated / status unusable
#
# On success prints: AGENT_USER=<email-or-unknown>
# On failure prints a reason on stderr. Callers must SKIP steps 6–7 (do not
# treat this as an adversary rejection).
set -euo pipefail

if ! command -v agent >/dev/null 2>&1; then
  echo "check_agent_cli.sh: Cursor 'agent' CLI not found on PATH — skip adversary review (steps 6–7)" >&2
  exit 1
fi

json_out=""
if json_out="$(agent status --format json 2>/dev/null)"; then
  authed="$(printf '%s' "$json_out" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
  print("true" if d.get("isAuthenticated") is True or d.get("status")=="authenticated" else "false")
except Exception:
  print("error")' 2>/dev/null || echo error)"
  if [ "$authed" = "true" ]; then
    user="$(printf '%s' "$json_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
u=d.get("userInfo") or {}
print(u.get("email") or u.get("userId") or "unknown")' 2>/dev/null || echo unknown)"
    echo "AGENT_USER=${user}"
    exit 0
  fi
  if [ "$authed" = "false" ]; then
    echo "check_agent_cli.sh: Cursor 'agent' is installed but not authenticated — skip adversary review (steps 6–7)" >&2
    echo "Run: agent login" >&2
    exit 2
  fi
fi

# Text fallback if --format json is unavailable.
status_out=""
status_ec=0
status_out="$(agent status 2>&1)" || status_ec=$?
if [ "$status_ec" -ne 0 ]; then
  status_out="$(agent whoami 2>&1)" || status_ec=$?
fi
if [ "$status_ec" -ne 0 ]; then
  echo "check_agent_cli.sh: 'agent status' failed (exit $status_ec) — skip adversary review (steps 6–7)" >&2
  echo "$status_out" >&2
  exit 2
fi
if printf '%s\n' "$status_out" | grep -qiE 'not logged in|unauthenticated|please log in|login required'; then
  echo "check_agent_cli.sh: 'agent' reports logged-out — skip adversary review (steps 6–7)" >&2
  echo "Run: agent login" >&2
  exit 2
fi
if ! printf '%s\n' "$status_out" | grep -qiE 'logged in|authenticated|signed in'; then
  echo "check_agent_cli.sh: could not confirm authentication — skip adversary review (steps 6–7)" >&2
  echo "$status_out" >&2
  echo "Run: agent login" >&2
  exit 2
fi
user="$(printf '%s\n' "$status_out" | grep -oiE 'logged in as [^[:space:]]+' | head -1 | sed 's/[Ll]ogged in as //')"
echo "AGENT_USER=${user:-unknown}"
exit 0
