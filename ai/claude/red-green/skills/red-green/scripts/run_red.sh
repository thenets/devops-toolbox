#!/usr/bin/env bash
# run_red.sh -p '<predicted-failure regex>' [-l logfile] -- <test command...>
#
# Verify a RED run: the test command must FAIL, and fail for the predicted
# reason. Enforces the discipline that a red is only a red when:
#   1. the command exits nonzero (a passing test reproduces nothing),
#   2. the output matches the failure you predicted BEFORE running,
#   3. the failure is not a compile/build/setup error in disguise.
#
# Exit codes: 0 red confirmed · 1 test passed (not red) · 2 failed but the
# predicted pattern is absent · 3 failure looks like a compile/build error
# and the predicted pattern is absent · 64 usage error.
set -u

pattern="" logfile=""
while getopts "p:l:" opt; do
  case "$opt" in
    p) pattern="$OPTARG" ;;
    l) logfile="$OPTARG" ;;
    *) exit 64 ;;
  esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift

if [ -z "$pattern" ] || [ $# -eq 0 ]; then
  echo "usage: run_red.sh -p '<predicted-failure regex>' [-l logfile] -- <test command...>" >&2
  echo "The -p prediction is mandatory: state how the test will fail BEFORE running it." >&2
  exit 64
fi

# Trailing Xs only: BSD mktemp does not substitute embedded X templates.
[ -n "$logfile" ] || logfile="$(mktemp "${TMPDIR:-/tmp}/red-run.XXXXXX")" || exit 64

echo ">>> RED run: $*"
"$@" >"$logfile" 2>&1
status=$?
tail -n 60 "$logfile"
echo ">>> exit=$status  full log: $logfile"

if [ "$status" -eq 0 ]; then
  echo "NOT RED: the test PASSED. It does not reproduce the bug — go back to reproduction; do not fix anything yet." >&2
  exit 1
fi

compile_re='syntax error|SyntaxError|cannot find symbol|cannot find package|undefined:|undeclared identifier|unresolved import|error\[E[0-9]+\]|error TS[0-9]+|ImportError|ModuleNotFoundError|compilation (failed|error)|compile error|linker command failed|ld: error|fatal error: .*(\.h|No such file)|expected .* before|does not compile|build error'

if grep -qiE "$pattern" "$logfile"; then
  if grep -qiE "$compile_re" "$logfile"; then
    echo "WARNING: predicted failure matched, but the log also contains compile/build-error markers — read the log and confirm the failure is the assertion, not the build." >&2
  fi
  echo "RED CONFIRMED: failed and matched predicted pattern: $pattern"
  exit 0
fi

if grep -qiE "$compile_re" "$logfile"; then
  echo "NOT RED: this looks like a COMPILE/BUILD error, not a failing assertion. A compile error proves nothing — make the tree build, or use the surgical-revert procedure (references/revert-red.md)." >&2
  exit 3
fi

echo "NOT RED (as predicted): the command failed, but the predicted pattern did not match: $pattern" >&2
echo "Your test does not bite what you think it bites. Read the log, understand the actual failure, and update the reproduction or the test before proceeding." >&2
exit 2
