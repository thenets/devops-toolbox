---
name: write-bash-scripts
description: Create, refactor, and review safe, maintainable Bash scripts and command-line utilities. Use for .sh files, Bash automation, script boilerplates, argument parsing, help output, logging, temporary-file cleanup, sourced-versus-executed behavior, terminal detection, retries, and ShellCheck-driven improvements.
---

# Write Bash Scripts

Build scripts with explicit interfaces, safe defaults, and tests appropriate to
their risk. Prefer the smallest script that clearly solves the task.

## Workflow

1. Read repository instructions and nearby scripts before choosing conventions.
2. Confirm that Bash is appropriate and identify the oldest supported Bash
   version and target operating systems.
3. Define inputs, outputs, exit codes, dependencies, side effects, and help text.
4. For a substantial new script, copy `assets/bash-script-template.sh` and remove
   unused sections. For a small script, implement only the required structure.
5. Read `references/patterns.md` when the task needs help generation, script-path
   resolution, sourcing detection, terminal-aware output, temporary files, or
   bounded retries.
6. Validate syntax with `bash -n`. Run ShellCheck when available. Exercise help,
   success, invalid-input, and expected-failure paths without invoking unsafe or
   production side effects.

## Implementation rules

- Use `#!/usr/bin/env bash` unless the environment requires a fixed interpreter.
- Start new standalone scripts with `set -Eeuo pipefail`; handle commands whose
  failure is expected inside conditionals instead of disabling error handling
  globally.
- Quote expansions and paths. Use arrays for command arguments.
- Never use `eval` to assemble a command.
- Use `local` inside functions and `readonly` for genuine constants.
- Send diagnostics and progress to stderr; reserve stdout for requested data.
- Validate arguments and external commands before performing side effects.
- Use `mktemp` and a trap for temporary resources. Make cleanup idempotent.
- Add bounded retries with a configurable delay. Return nonzero after exhaustion.
- Keep color optional and emit it only for a terminal that supports `tput`.
- Guard `main "$@"` when a file is intended to be both sourced and executed.
- Do not hide errors with broad redirection. Suppress only understood output.
- Avoid parsing `ls`, unquoted command substitution, and pipelines whose failure
  behavior is unclear.

## Review checklist

- Confirm paths and values containing whitespace or glob characters work.
- Confirm missing variables, missing commands, and interrupted runs fail cleanly.
- Confirm output remains useful when piped or redirected.
- Confirm secrets are absent from logs and command traces.
- Confirm the script preserves unrelated files and is idempotent when practical.
- Preserve executable mode for executable scripts.

## Resources

- `assets/bash-script-template.sh`: copy-ready standalone CLI template.
- `references/patterns.md`: focused Bash patterns derived from this repository's
  former examples and boilerplate.
