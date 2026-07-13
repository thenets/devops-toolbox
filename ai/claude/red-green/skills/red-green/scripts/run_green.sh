#!/usr/bin/env bash
# run_green.sh [-l logfile] -- <test command...>
#
# Verify a GREEN run: the command must exit 0. Use it twice after the fix —
# once on the red test, once on the full suite for the affected module.
#
# Exit codes: 0 green confirmed · 1 still failing · 64 usage error.
set -u

logfile=""
while getopts "l:" opt; do
  case "$opt" in
    l) logfile="$OPTARG" ;;
    *) exit 64 ;;
  esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift

if [ $# -eq 0 ]; then
  echo "usage: run_green.sh [-l logfile] -- <test command...>" >&2
  exit 64
fi

# Trailing Xs only: BSD mktemp does not substitute embedded X templates.
[ -n "$logfile" ] || logfile="$(mktemp "${TMPDIR:-/tmp}/green-run.XXXXXX")" || exit 64

echo ">>> GREEN run: $*"
"$@" >"$logfile" 2>&1
status=$?
tail -n 40 "$logfile"
echo ">>> exit=$status  full log: $logfile"

if [ "$status" -ne 0 ]; then
  echo "NOT GREEN: still failing (exit $status). Fix product code — never edit the test to make it pass." >&2
  exit 1
fi

echo "GREEN CONFIRMED."
