# Reproducing in a live environment

Reproduce in the running product before theorizing from source. Static reading
regularly finds nothing wrong while the running app is provably broken; the
live system can be interrogated, the source can only be interpreted.

## Why this step exists

- A poll loop whose subprocesses stop appearing is dead, whatever the source
  says. Observing the product falsifies hypotheses cheaply.
- "Works in tests, broken in the app" is often a **stale or mismatched
  artifact** — check the running binary's version/mtime against the source
  before hunting for a code bug.
- Two symptoms filed as two bugs are often one dead component. The live system
  shows the shared failure; the source shows two innocent-looking call sites.

## Tactics by surface

**CLI / batch**: run the exact reported invocation, verbatim, in a scratch
directory. Capture stdout/stderr/exit code. Then minimize: shrink the input
until the one-sentence reproduction is obvious.

**Server / API**: start it locally (or find the running instance), replay the
failing request with `curl`/a client, watch the logs at debug level while the
request lands. Compare a passing request's log trail against the failing one.

**Daemon / long-running process**: check it is actually alive and doing its
periodic work — do its side effects still appear (child processes, log lines,
file writes, sockets)? Useful probes: `ps` in a watch loop, `lsof -p <pid>`,
`sample <pid>` (macOS) or `gdb -p`/`eu-stack`/`jstack` (Linux/JVM), `strace`/
`dtruss` for syscall-level truth.

**UI**: drive the real app (browser via Playwright-type tooling, or the actual
desktop app) to the reported state; screenshot the wrong behavior. Console/
devtools errors count as evidence.

**Freeze / stall**: reproduction means naming the stuck frame. Take a stack
sample of the wedged process; "worker parked in `waitUntilExit` while the child
is gone" is a reproduction, "the sidebar is slow" is not.

**Flaky test**: run it in a loop (`-count=100`, `--repeat`, a shell loop) and
under the race detector / sanitizers if the language has one, until you have a
failure you can summon on demand — or at least a failure rate you can measure
before and after the fix.

## When live repro is impossible

Needs production credentials, real customer data, specific hardware, a real
CA, a third-party outage. Then:

- say so explicitly in the worksheet and the final report,
- lean on the strongest recorded evidence (logs, stack traces, core dumps,
  monitoring graphs) and cite it,
- make the red test encode that evidence (feed the logged input to the code
  path; assert the logged wrong output).
