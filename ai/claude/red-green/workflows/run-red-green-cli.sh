#!/usr/bin/env bash
# Convenience launcher next to red-green-workflow.js for Cursor CLI users.
# Delegates to the skill's orchestrator (same phases as the JS Workflow file).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/skills/red-green/scripts/run_workflow_cli.sh" "$@"
