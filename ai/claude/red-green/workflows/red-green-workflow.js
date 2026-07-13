export const meta = {
  name: 'red-green-workflow',
  description: 'Multi-agent red-green bug fix: parallel investigation, adversarially verified diagnosis, red test, fix, green verification, review',
  whenToUse: 'Complex bugs — unknown root cause, multiple symptoms, cross-component failures, races. Simple bugs: fix inline with the red-green skill instead.',
  phases: [
    { title: 'Investigate', detail: 'parallel evidence gathering: code, history, live system, test harness' },
    { title: 'Diagnose', detail: 'independent hypotheses, adversarially refuted' },
    { title: 'Red', detail: 'failing regression test, verified to fail for the predicted reason' },
    { title: 'Fix', detail: 'minimal root-cause fix, product code only' },
    { title: 'Green', detail: 'test + suite pass, adversarial review' },
  ],
}

// ---- input ----------------------------------------------------------------
const input = typeof args === 'string' ? { bug: args } : (args || {})
const bug = input.bug
if (!bug) throw new Error('args.bug is required: verbatim symptom plus everything already known')
const repo = input.repoPath || '.'
const scriptsDir = input.scriptsDir || ''
const knownTestCommand = input.testCommand || ''
const liveRepro = input.liveRepro || ''

const CTX = `Repository root: ${repo}
Bug report (verbatim, plus what is already known):
${bug}
${liveRepro ? `How to run/observe the live product: ${liveRepro}` : ''}
${knownTestCommand ? `Known full-suite test command: ${knownTestCommand}` : ''}`

const REDGREEN_RULES = `Red-green rules (non-negotiable):
- A red is only a red when the test FAILS with the assertion you predicted BEFORE running it. A passing test, a compile/build error, or a setup crash is NOT a red.
- Fix product code only; never edit a test to make it pass.
- Name tests after the bug, assert behavior not implementation, use the cheapest tier (unit before integration) that can actually fail on this bug.
${scriptsDir ? `- Verify runs with the helper scripts: '${scriptsDir}/run_red.sh -p <predicted-failure-regex> -- <cmd>' and '${scriptsDir}/run_green.sh -- <cmd>'.` : ''}`

// ---- schemas ---------------------------------------------------------------
const EVIDENCE = {
  type: 'object', required: ['summary', 'facts'],
  properties: {
    summary: { type: 'string' },
    facts: { type: 'array', items: { type: 'object', required: ['fact', 'evidence'], properties: {
      fact: { type: 'string' }, evidence: { type: 'string', description: 'file:line, command output, or log excerpt backing the fact' } } } },
    reproducedLive: { type: 'boolean' },
    reproSteps: { type: 'string' },
  },
}
const HYPOTHESIS = {
  type: 'object', required: ['rootCause', 'mechanism', 'location', 'confidence'],
  properties: {
    rootCause: { type: 'string' },
    mechanism: { type: 'string', description: 'step-by-step: how this cause produces every reported symptom' },
    location: { type: 'string', description: 'file:line (or component) of the defect' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    disconfirmingCheck: { type: 'string', description: 'a concrete check that would refute this hypothesis if it is wrong' },
  },
}
const VERDICT = {
  type: 'object', required: ['refuted', 'reason'],
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' } },
}
const RED_RESULT = {
  type: 'object', required: ['isRed', 'testFiles', 'testCommand', 'predictedFailure', 'observedFailure'],
  properties: {
    isRed: { type: 'boolean' },
    testFiles: { type: 'array', items: { type: 'string' } },
    testCommand: { type: 'string', description: 'exact command that runs just the new test(s)' },
    predictedFailure: { type: 'string' },
    observedFailure: { type: 'string', description: 'the actual failure output excerpt' },
    mode: { type: 'string', enum: ['test-first', 'surgical-revert', 'invariant-guard'] },
    notes: { type: 'string' },
  },
}
const FIX_RESULT = {
  type: 'object', required: ['filesChanged', 'description'],
  properties: { filesChanged: { type: 'array', items: { type: 'string' } }, description: { type: 'string' } },
}
const GREEN_RESULT = {
  type: 'object', required: ['redTestPasses', 'suitePasses', 'suiteCommand', 'output'],
  properties: {
    redTestPasses: { type: 'boolean' }, suitePasses: { type: 'boolean' },
    suiteCommand: { type: 'string' }, output: { type: 'string' },
    failures: { type: 'string', description: 'if anything failed: exact test names + assertions' },
  },
}
const REVIEW = {
  type: 'object', required: ['ok', 'findings'],
  properties: { ok: { type: 'boolean' }, findings: { type: 'array', items: { type: 'string' } } },
}

// ---- Phase 1: Investigate ---------------------------------------------------
phase('Investigate')
log('Fanning out evidence gathering: code, history, live system, test harness')

const investigators = [
  { label: 'inv:code', prompt: `${CTX}\n\nInvestigate the CODE implicated by this bug. Locate the components/functions on the failing path, read them, and trace the data/control flow that could produce the symptom. Return concrete facts with file:line evidence — no speculation without a marked check. Do NOT modify any file.` },
  { label: 'inv:history', prompt: `${CTX}\n\nInvestigate the HISTORY. Use git log/blame/diff around the implicated area: what changed recently, when the symptom plausibly started, suspicious commits, related past fixes or reverted changes. Return facts with commit hashes / file:line as evidence. Do NOT modify any file.` },
  { label: 'inv:live', prompt: `${CTX}\n\nReproduce the bug in a LIVE environment if at all possible: run the exact failing invocation/request/flow, capture output, logs, exit codes, process state (for a hang: a stack sample naming the stuck frame). Minimize to the smallest reproduction. Check the running artifact matches the source (stale-binary check). If live repro is impossible here, say exactly why and gather the strongest recorded evidence instead (logs, traces). You may run the product and create scratch files, but do NOT modify repo source files. Set reproducedLive and reproSteps accordingly.` },
  { label: 'inv:harness', prompt: `${CTX}\n\nInvestigate the TEST HARNESS. How are tests written and run in this repo (README, CLAUDE.md, CI config, Makefile${scriptsDir ? `; '${scriptsDir}/detect_stack.sh ${repo}' can help` : ''})? Report: full-suite command, single-test command syntax, test file conventions near the implicated code, existing tests that almost cover this bug, and the cheapest tier at which this bug could be exercised. Do NOT modify any file.` },
]

// Barrier justified: Diagnose needs the union of all evidence.
const evidence = (await parallel(investigators.map(i => () =>
  agent(i.prompt, { label: i.label, phase: 'Investigate', schema: EVIDENCE })
))).filter(Boolean)
if (evidence.length === 0) throw new Error('all investigators failed')

const evidenceText = evidence.map((e, i) =>
  `--- Evidence set ${i + 1} (${investigators[i] ? investigators[i].label : 'unknown'}) ---\n${e.summary}\n${e.facts.map(f => `* ${f.fact} [${f.evidence}]`).join('\n')}${e.reproSteps ? `\nRepro steps: ${e.reproSteps}` : ''}`
).join('\n\n')
const live = evidence.find(e => e.reproducedLive)
log(live ? 'Bug reproduced live' : 'No live reproduction yet — diagnosing from recorded evidence')

// ---- Phase 2: Diagnose --------------------------------------------------------
phase('Diagnose')
const LENSES = [
  { key: 'recent-change', angle: 'a recent code/config/dependency change regressed previously-working behavior' },
  { key: 'state-lifecycle', angle: 'a state machine, lifecycle, ordering, or concurrency flaw that was always latent' },
  { key: 'environment', angle: 'environment/config/artifact mismatch: stale binary, platform difference, bad input contract, external dependency' },
]

let winner = null
let refutations = []
for (let round = 0; round < 2 && !winner; round++) {
  const extra = refutations.length
    ? `\nPrior hypotheses were REFUTED for these reasons — do not repeat them, account for them:\n${refutations.join('\n')}`
    : ''

  // pipeline: each lens's hypothesis goes straight to its refuters, no barrier
  const judged = (await pipeline(
    LENSES,
    lens => agent(
      `${CTX}\n\nAll gathered evidence:\n${evidenceText}${extra}\n\nPropose the single most plausible ROOT CAUSE through this lens: ${lens.angle}. Read the actual code at the location you name — do not diagnose from the evidence text alone. The mechanism must explain EVERY reported symptom; if it cannot, say so and lower confidence. Do NOT modify any file.`,
      { label: `hypothesis:${lens.key}`, phase: 'Diagnose', schema: HYPOTHESIS },
    ),
    (hyp, lens) => hyp && parallel([0, 1].map(n => () =>
      agent(
        `${CTX}\n\nEvidence:\n${evidenceText}\n\nHypothesis under test (lens ${lens.key}): root cause "${hyp.rootCause}" at ${hyp.location}; mechanism: ${hyp.mechanism}\n\nYou are adversarial verifier #${n + 1}. Try to REFUTE it: read the code at the named location, check the mechanism step by step against the evidence, and run the disconfirming check: ${hyp.disconfirmingCheck || 'devise one'}. Default to refuted=true if the mechanism does not fully explain the symptoms or the code does not say what the hypothesis claims. Do NOT modify any file.`,
        { label: `refute:${lens.key}#${n + 1}`, phase: 'Diagnose', schema: VERDICT },
      )
    )).then(vs => ({ hyp, lens: lens.key, verdicts: vs.filter(Boolean) })),
  )).filter(Boolean)

  const survivors = judged.filter(j => j.verdicts.length && j.verdicts.every(v => !v.refuted))
  refutations = judged.flatMap(j => j.verdicts.filter(v => v.refuted).map(v => `- [${j.lens}] "${j.hyp.rootCause}": ${v.reason}`))

  if (survivors.length) {
    const order = { high: 0, medium: 1, low: 2 }
    survivors.sort((a, b) => (order[a.hyp.confidence] ?? 3) - (order[b.hyp.confidence] ?? 3))
    winner = survivors[0]
    log(`Diagnosis (survived adversarial review, lens ${winner.lens}): ${winner.hyp.rootCause}`)
  } else if (round === 0) {
    log('All hypotheses refuted — one more round, informed by the refutations')
  }
}

if (!winner) {
  return {
    status: 'undiagnosed',
    message: 'No root-cause hypothesis survived adversarial verification after two rounds. Do not fix on a guess — investigate further with the leads below.',
    evidence: evidence.map(e => e.summary),
    refutations,
  }
}
const diagnosis = winner.hyp

// ---- Phase 3: Red ---------------------------------------------------------------
phase('Red')
let red = null
let redFeedback = ''
for (let attempt = 0; attempt < 3 && !(red && red.isRed); attempt++) {
  red = await agent(
    `${CTX}\n\nDiagnosed root cause: ${diagnosis.rootCause} at ${diagnosis.location}. Mechanism: ${diagnosis.mechanism}\n\nHarness facts:\n${evidenceText}\n\n${REDGREEN_RULES}\n\nWrite the RED regression test for this bug, following the repo's existing test conventions, at the cheapest tier that can exercise it. Steps: (1) write the test asserting the CORRECT behavior; (2) state the exact predicted failure BEFORE running; (3) run it and confirm it fails with exactly that assertion. If the test cannot exist before the fix (needs a new symbol to compile), use surgical-revert mode: note it, and the fix phase will handle ordering. If the bug is non-deterministic, test the invariant the fix will establish and/or a guard test — mode invariant-guard. Do NOT write the fix. Do NOT weaken the assertion to make failing easier.${redFeedback ? `\n\nA verifier rejected the previous attempt: ${redFeedback}\nAddress that.` : ''}`,
    { label: `red:write#${attempt + 1}`, phase: 'Red', schema: RED_RESULT },
  )
  if (!red) continue
  if (red.mode === 'surgical-revert') break // ordering handled after the fix
  const check = await agent(
    `${CTX}\n\n${REDGREEN_RULES}\n\nA red test was just added: files ${JSON.stringify(red.testFiles)}, command: ${red.testCommand}\nPredicted failure: ${red.predictedFailure}\nClaimed observed failure: ${red.observedFailure}\n\nAdversarially verify the red is genuine: re-run the command yourself${scriptsDir ? ` (use '${scriptsDir}/run_red.sh -p <regex> -- ${red.testCommand}')` : ''} and confirm (a) it fails, (b) the failure is the predicted assertion — not a compile/build error, setup crash, or unrelated failure — and (c) reading the test, it actually encodes the diagnosed bug (${diagnosis.rootCause}) and asserts behavior, not implementation detail. refuted=true if any check fails, with the exact reason. Do NOT modify any file.`,
    { label: `red:verify#${attempt + 1}`, phase: 'Red', schema: VERDICT },
  )
  if (check && check.refuted) {
    redFeedback = check.reason
    red.isRed = false
    log(`Red rejected: ${check.reason}`)
  } else if (check) {
    red.isRed = true
  }
}
if (!red || (!red.isRed && red.mode !== 'surgical-revert')) {
  return { status: 'no-red', message: 'Could not produce a verified failing test after 3 attempts. Diagnosis stands but is unproven — do not fix without a red.', diagnosis, lastAttempt: red, redFeedback }
}

// ---- Phase 4: Fix ------------------------------------------------------------------
phase('Fix')
const fix = await agent(
  `${CTX}\n\nDiagnosed root cause: ${diagnosis.rootCause} at ${diagnosis.location}. Mechanism: ${diagnosis.mechanism}\nRed test: files ${JSON.stringify(red.testFiles)}, command: ${red.testCommand}, mode: ${red.mode}\n\n${REDGREEN_RULES}\n\nImplement the MINIMAL fix for the root cause. Product code only — do not touch the test files. Do not refactor beyond the fix. Match the surrounding code's style.${red.mode === 'surgical-revert' ? `\n\nThis is surgical-revert mode: after fixing and going green, verify the red by surgically reverting the BEHAVIOR (keep the tree compiling: flip a condition, not delete the function), predicting the exact failure set, running, requiring an exact match, then restoring and re-running green. Record predicted vs observed in your result description.` : ''}`,
  { label: 'fix', phase: 'Fix', schema: FIX_RESULT },
)
if (!fix) return { status: 'fix-failed', message: 'Fix agent failed.', diagnosis, red }

// ---- Phase 5: Green -----------------------------------------------------------------
phase('Green')
let green = null
for (let attempt = 0; attempt < 3; attempt++) {
  green = await agent(
    `${CTX}\n\nA fix for "${diagnosis.rootCause}" changed: ${JSON.stringify(fix.filesChanged)}. The regression test: ${red.testCommand}\n\nVerify GREEN: (1) run the regression test${scriptsDir ? ` via '${scriptsDir}/run_green.sh -- ${red.testCommand}'` : ''} — it must pass; (2) find and run the FULL test suite for the affected module/project (${knownTestCommand || 'discover the suite command from Makefile/CI/README'}) — it must pass. Report exact commands, results, and on failure the exact failing test names + assertions. Do NOT modify any file.`,
    { label: `green:run#${attempt + 1}`, phase: 'Green', schema: GREEN_RESULT },
  )
  if (green && green.redTestPasses && green.suitePasses) break
  if (attempt === 2) break
  log(`Not green yet: ${green ? green.failures || 'runner failed' : 'runner failed'} — repairing`)
  await agent(
    `${CTX}\n\nRoot cause: ${diagnosis.rootCause}. Fix so far changed: ${JSON.stringify(fix.filesChanged)}.\nGreen verification failed:\n${green ? green.output : '(runner produced no output)'}\nFailures: ${green ? green.failures || '' : ''}\n\n${REDGREEN_RULES}\n\nRepair the FIX (product code only — never the tests) so both the regression test and the full suite pass. If a suite failure reveals the fix is wrong rather than incomplete, say so plainly in your description instead of forcing it.`,
    { label: `fix:repair#${attempt + 1}`, phase: 'Green', schema: FIX_RESULT },
  )
}

// Independent quality review, two lenses in parallel (both read-only).
const reviews = (await parallel([
  () => agent(
    `${CTX}\n\nReview the new regression TEST for this fix: files ${JSON.stringify(red.testFiles)} (root cause was: ${diagnosis.rootCause}). Lens: test quality. Does it assert behavior (not implementation)? Is it named after the bug? Would it survive a reasonable refactor of the fix? Is every wait bounded (no possible hang)? Would it really catch the bug's return? findings = concrete problems only. Do NOT modify any file.`,
    { label: 'review:test', phase: 'Green', schema: REVIEW },
  ),
  () => agent(
    `${CTX}\n\nReview the FIX: files ${JSON.stringify(fix.filesChanged)} (diagnosis: ${diagnosis.rootCause}; mechanism: ${diagnosis.mechanism}). Lens: fix quality. Does it address the root cause or mask the symptom? Could it regress adjacent behavior (read the call sites)? Is it minimal? findings = concrete problems only. Do NOT modify any file.`,
    { label: 'review:fix', phase: 'Green', schema: REVIEW },
  ),
])).filter(Boolean)

const isGreen = !!(green && green.redTestPasses && green.suitePasses)
return {
  status: isGreen ? 'green' : 'red-fix-not-green',
  reproduction: { live: !!live, steps: live ? live.reproSteps : '(not reproduced live — see evidence)' },
  diagnosis: { rootCause: diagnosis.rootCause, location: diagnosis.location, mechanism: diagnosis.mechanism, lens: winner.lens },
  red: { mode: red.mode || 'test-first', testFiles: red.testFiles, testCommand: red.testCommand, predictedFailure: red.predictedFailure, observedFailure: red.observedFailure },
  fix: { filesChanged: fix.filesChanged, description: fix.description },
  green: green || { redTestPasses: false, suitePasses: false, output: 'green runner failed' },
  reviewFindings: reviews.flatMap(r => r.findings || []),
  caveats: isGreen ? [] : ['Green verification did NOT fully pass — do not present this as a verified fix.'],
}
