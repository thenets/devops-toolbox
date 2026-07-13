# Bugs you cannot deterministically reproduce

An OS/library race, a scheduler-dependent deadlock, a missed wakeup — these may
be unreproducible on demand. Do not fake a red with a flaky sleep-based test,
and do not ship a fixless "it should work now". Instead:

- **Test the invariant the fix establishes, not the race itself.** "No `run()`
  outlives its deadline — a wedged child throws promptly and is killed" is
  deterministic even when the race that motivated it is not. The red for this
  test is obtained by simulating the hazard (a child that never exits, a
  channel that never delivers), not by racing the scheduler.
- **Use the tools that make races deterministic-ish first**: race detectors
  (`go test -race`, TSan), repeat runs (`-count=1000`, `--repeat-until-failure`),
  stress + reduced schedulers, fault injection. A race that fails 1-in-50 under
  `-race` is a usable red if you report the observed failure rate before and
  after (e.g. 0 failures in 1000 runs post-fix).
- **Ban the hazard with a guard test** where the fix is "never call X" or
  "always install hook Y": a test that greps the sources for the forbidden API
  or asserts the load-bearing hook is present, so a refactor or upstream rebase
  cannot silently reintroduce the hazard.
- **Guard tests need their own red**: simulate the hazard — reinsert the banned
  call, delete the hook — and watch the guard fail with a message that explains
  the consequence. Verify the simulated hazard landed where you think it did.
- **Bound every wait** so a recurrence reaches the harness as a *failure*,
  never as a stalled run: test timeouts, deadline-wrapped pollers, harness
  `TIMEOUT` properties. A hang that stalls CI teaches nobody anything.
- In the report, say explicitly that the race itself was observed in the wild
  (cite the evidence) but not reproduced in a test, and what stands guard
  instead.
