> Redacted historical observation: identifiers removed; originals remain private. Current behavior is defined by the v4 documentation.

# Fresh-Conversation Canary — 2026-09-05

## Routing Result

The test used a new Antigravity conversation and did not name Tier 1, the
router, or the target Skill. Before a multi-step TEMP-only write task,
Antigravity inspected `GEMINI.md` and fully read
`skills/reliable-maker-control/SKILL.md`.

Result:

```text
conditional Tier 1 discovery: live-observed in one fresh session
enforcement mode: policy-only
repeatability: not yet measured
```

## Governed Execution Finding

The same run manually created an Attempt Ledger and invoked only the completion
report renderer. The TEMP task contained no canonical Task Contract,
Verification Envelope, Completion Claim, or Completion Decision, while the
natural-language report claimed that the full governance and Completion Gate
had run.

Observed artifact availability:

```text
contract: missing
ledger: present, manually assembled
report: present
structured test result: present
verification envelope: missing
completion claim: missing
completion decision: missing
```

This is a phantom-execution regression: reading policy and producing similar
JSON is not equivalent to invoking canonical scripts.

## Decision

```text
autonomous routing: keep, live-observed once
test implementation: passed in TEMP
governed execution claim: reject
final natural-language report: revise
overall: checking
```

The finding motivated v2.3 producer hashes and
`audit-governed-execution.ps1`. The original TEMP payload remains outside
source and is referenced only by sanitized facts in this document.
# Fresh-window governed execution Canary: v2.3 findings

The fresh conversation autonomously read `reliable-maker-control` and produced
a substantially complete contract, attempt ledger, structured test result,
verification envelope, completion report, checking decision, and audit result.
Independent inspection confirmed the reported hashes and the final
`passed_after_retry` history in the second TaskRoot.

The Canary also exposed four gaps addressed in v2.4:

- empty project baselines failed because an empty pipeline serialized to null;
- the first TaskRoot could be abandoned without linking its failures to the
  replacement TaskRoot;
- the Scope Guard was observed after writes but could be described as a
  pre-write control;
- Completion Claim JSON was manually assembled and had no canonical producer.

The old v2.3 Canary chain remains historical evidence. Under v2.4 it does not
pass the stronger provenance audit because it predates the TaskRoot manifest
and canonical Claim producer requirements.
# Fresh-window v2.4 full-chain Canary: independent finding

The v2.4 Canary correctly proved empty TaskRoot bootstrap, rejected a silent
TaskRoot switch, distinguished pre-write declaration from post-write
observation, generated a canonical Completion Claim, and stopped at
`checking`. Its product test result and most reported hashes were accurate.

Independent timestamp and ledger inspection found one remaining false-negative:
Attempt 1 started before the test file was created, but closed with
`workspace_after_sha256: null`, no changed paths, and
`side_effects_observed: false`. The test file was created during that failed
Attempt. The cause was a PowerShell truthiness check that skipped after-snapshot
collection when the valid before snapshot was an empty array.

v2.5 fixes empty-array snapshot serialization, always observes the after state
for ProjectRoot-backed terminal Attempts, and makes the Completion Gate and
governed-execution audit reject incomplete or internally inconsistent Attempt
observations. The v2.4 Canary remains useful historical evidence but is not
accepted as a v2.5-complete governed chain.

The prompt explicitly named the Tier 1 Skill path, so this Canary proves
prompt-directed Skill loading, not autonomous conditional discovery.
# Fresh-window v2.5 Canary: router success and bootstrap escape

The v2.5 Canary independently confirms router-directed loading of
`reliable-maker-control`: the user prompt did not name the Skill or its path,
the agent read `GEMINI.md`, followed the Tier router, and then read the
installed Skill. It also correctly recorded a failed Attempt with a nonzero
exit and a created test-file side effect, then completed a valid
`passed_after_retry` chain that stopped at `checking`.

The final report nevertheless omitted two earlier governed roots. The agent
generated a large TEMP runner, executed it, encountered a PowerShell expression
error, rewrote the runner, and retried. Each retry generated a new timestamped
LogicalTaskId and a new per-run RegistryRoot. Two abandoned roots already
contained TaskRoot manifests and Contracts but no Attempt Ledger or completion
record. The third root succeeded and was the only one reported.

v2.6 adds a normalized task-intent index under the private RegistryRoot.
Equivalent objective, non-goals, scope, checks, and budgets cannot be made into
a fresh active task merely by changing LogicalTaskId. The audit also requires a
TaskRoot intent hash. This remains script-enforced-on-invocation; a wrapper
failure before any governed bootstrap cannot be captured without host support.
