#!/usr/bin/env bash
# run_workflow_cli.sh — thin entrypoint for the Cursor CLI red-green orchestrator.
#
# See references/workflow-cli.md and run_workflow_cli.py --help.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/run_workflow_cli.py" "$@"
