# v4 Completion Gate and bounded Stop

Status: implemented and locally tested; Desktop Stop activation is **unverified**.
No Stop event is registered in hooks.json. A caller must use the documented local
evaluator explicitly; it is not a host control guarantee.

## Explicit chain

Use the same logical TaskId as ContractId. Verification now accepts TaskId,
TaskAttemptId and ContractPath together. Its task_binding records those task
references plus the contract hash before execution and checks that hash afterward.
The envelope still records its own independent run id, not a Task Attempt id.

Canonical claims reference a contract, current test result, run id, task id,
task attempt id, ledger, report and envelope. Gate validates the exact referenced
files, current producer version, current source/test content and last-write times,
required checks, all structured case outcomes, contract/project/task identities,
and the report's full ledger projection. The result file must have been written
inside that envelope's execution window. A changed verifier, test, source or
evidence file requires a new envelope and claim.

`audit-governed-execution.ps1 -TaskRoot <root> -DecisionPath <exact decision>`
replays the selected chain read-only through `invoke-completion-gate.ps1 -ReadOnly`.
No component searches for the newest JSON. Missing selection is a visible failure.
Source-only deterministic success stays `checking` with authority `unverified`.
Producer hashes describe version/integrity, not identity signatures.

Claim output uses create-new semantics and refuses replacement. A repair can
include PreviousClaimPath and PreviousDecisionPath, retaining their exact hashes.
Each ordinary Gate invocation emits a new decision; read-only audit emits none.
Callers must retain and explicitly supply repair references; same-user state can
still be altered and there is no independent immutable global history authority.

## Bounded Stop

`invoke-bounded-stop.ps1 -StatePath <fixed task state> -TaskId <same task> -DecisionStatus unverified`
requests a check at most twice. The third unsuccessful evaluation returns stop /
blocked. Passing deterministic evidence (`checking`) permits stop, never verified.
UserCancelled and EmergencyDisabled return stop before reading dependencies or
state. Malformed state, identity mismatch, aliases or unavailable locks stop as
blocked. State transitions use the shared bounded lock and atomic writer, preserving
prior snapshots. A caller must reuse the state path; arbitrary same-user tampering
or choosing a new path is not prevented by these scripts.

## Tests and limitations

Run `powershell.exe -NoProfile -File src/harness-evals/test-v4-completion.ps1`,
`test-verification-plane.ps1`, and `test-execution-provenance.ps1` from the repo.
The first suite retains isolated synthetic fixtures; no real task or transcript
is copied. Suite/case counts are not measured line or requirement coverage.

Shared path primitives reject ADS, reparse and hardlink aliases. This is guarded
admission, not an OS isolation boundary; same-identity concurrent replacement and
forged internally consistent records remain limitations. No host Stop behavior,
model truthfulness, independent reviewer identity or semantic correctness is
established. Optional `-ToolOperationPaths` creates forward Claim references with
path/hash/id/task/attempt fields. Gate validates each current record with the shared
typed operation validator and reducer, refuses unresolved/unclassified or replaced
records, and retains failed/denied records. It never mutates operations to add
backlinks, which would invalidate pinned hashes. Paths can reference the task or
configured private event root. Coverage is `explicit_subset`, never proof of all
host calls; omitted paths are `not_supplied`. Tool Operation completed alone never
counts as task acceptance. A later Post requires a new claim referencing new bytes.
