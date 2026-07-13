# Revert-red: when the test cannot exist before the fix

Sometimes the red test needs the fix to even compile — a new parameter, a new
function, a new seam. Writing the test first just yields a compile error, which
proves nothing. The legitimate order is then:

1. **Write the fix and the tests together**; get everything green.
2. **Surgically revert the behavior, not the code.** Keep the tree compiling:
   flip a condition to a tautology, push a deadline out by 99999s, compare
   against an impossible value — never delete the function the tests call.
   A revert that breaks the build re-runs stale binaries and lies (test
   harnesses that cache builds will happily report "Passed" from the previous
   binary).
3. **Predict the exact failure set, run, and require an exact match** — every
   reverted behavior's tests red, everything else green. If you reverted
   several behaviors, batch the reverts into one run; the exact-match check is
   what catches a test accidentally coupled to the wrong behavior.
   (`run_red.sh -p` works here too — the prediction is the set of failing
   test names/assertions.)
4. **Restore the fix, re-run, confirm green.**

Report this as **"red-verified by surgical revert"**, listing predicted vs
observed failures. It is equal in standing to test-first red; skipping it is
not.

Pitfall: verify your revert landed where you think. An edit inserted into the
wrong scope (a protocol/interface body instead of the implementation) may fail
to compile — and a compile error proves nothing.
