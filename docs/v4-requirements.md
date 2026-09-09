# v4 requirements → implementation → tests → evidence

The unified execution plan is `artifacts/plan_v4_convergence.md`. This is the
current acceptance mapping, not a claim of complete security or code coverage.
Case IDs below are executable assertions; release suite totals are not coverage.

| Work package | Implementation | Regression owner | Evidence / remaining host boundary |
|---|---|---|---|
| A project policy / binding | plugin hooks/control-lib.ps1; register-desktop-project.ps1; new-desktop-session-binding.ps1 | test-v4-policy.ps1, test-v4-control.ps1 | local regression plus five scoped live lifecycle stages; see production-readiness.md |
| B opaque execution / control plane | guarded denies arbitrary terminal and opaque subagent calls associated with protected project/binding; native control path checks | B-* rows plus hardlink/junction/ADS tests | strict unavailable; same-user external tool/terminal tampering and host TOCTOU not prevented |
| C operations / recovery | Add-AgOperation, locked flushed atomic files, callback reducer, read-only audit-desktop-hook-session.ps1 | test-v4-events.ps1 + C-* policy/control rows | restart, missing/late/orphan/duplicate/concurrent, corrupt/pending, held stdin, privacy; no immutable storage claim |
| D completion / Stop | explicit chain and bounded local evaluator; see v4-completion.md | test-v4-completion.ps1, migrated verification/provenance tests | valid local chains may reach checking; actual historical acceptance remains unverified; no trusted checker/native Stop |
| E knowledge | optional src/adapters/knowledge-gate | test-v4-knowledge.ps1 | artifact schemas, duration/hash/truth/critic/final surfaces/links/timestamps/install; image/video semantic work blocked |
| F release / rollback | existing sync-to-runtime and install-desktop-hook-plugin | test-v4-deployment.ps1, deploy/test-v4-runtime-sync.ps1, test-sync-boundaries.ps1 | staging/fault/rollback/hash; hard crash may require explicit journal rollback |
| Historical canary | frozen projection from original private correlations | test-v4-historical-replay.ps1 | replay only; original SHA/Attempt unchanged, not rerun |

## Fixed matrix and known limits

## Disposition of the twelve initial findings

| Finding | What was actually established | Closure evidence |
|---|---|---|
| 1 outer Pre allow override | Executed RED: unwritable state let protected write through | test-v4-control logging-failure now deny |
| 2 terminal bypass | Source inspection: v3 binding branch only matched native write tools | B terminal/nested-binding cases; guarded denies opaque entry, strict unavailable |
| 3 stale Contract hash | Source inspection: registration hash was not revalidated by old admission | A contract-tamper and current checks |
| 4 same-user mutable control | No independent identity/OS boundary established; not disguised by role IDs | strict registration returns unavailable; guarded limitations retained |
| 5 empty/bad JSON success | Executed RED for both; independent later string-boolean corruption repro | empty/corrupt/typed audit and writer tests |
| 6 newest evidence selection | Source inspection and RED plus old fabricated-producer fixture | explicit DecisionPath audit; real canonical positive, old fixture rejected |
| 7 check-then-write race | Source inspection plus independently reproduced new-lock contention regression | process duplicate/concurrent tests and acquired-handle fix |
| 8 output text authority | Inspected old regex-dependent classification; no reliable child exit channel established | forged-output/unknown/error-shape tests; opaque results unclassified |
| 9 tool success vs acceptance | Kept as a semantic boundary, never promoted by version naming | operation/Attempt separation and source-only checking tests |
| 10 contradictory docs | Read and compared actual context with installed files and old Canary | current-only CONTEXT; preserved changelog/history snapshots |
| 11 suite counts overstated | No measured code or exhaustive requirement coverage exists | reports explicitly say unmeasured; 21 suite count is not percent coverage |
| 12 knowledge mechanical gap | New isolated fixtures and independent negative repros | 37 knowledge cases; real media semantics/vault remain blocked/not authorized |

Some findings were established by source inspection rather than executing their
old unsafe path against a live desktop. Historical Canary was only replayed in a
fixture. No synthetic test is described as a fresh live-host reproduction.

- Authorization: unbound, active, terminal, revoked, expired, contract tamper,
  wrong/conflicting role, task mismatch, read-only, outside scope, relative/case,
  ADS, device/reparse/junction/hardlink aliases, renewal and narrowing.
- Execution: native writes, opaque run_command/subagent denial in guarded context,
  native control-plane paths. Cwd is never treated as complete write scope.
- Events: same/different operation concurrency, duplicates, Pre after Post, missing
  and delayed Post, cancellation-error and timeout/no-Post observations, malformed
  error field, logging failure, bad JSON, interrupted atomic commit, restart.
- Completion: current explicit chain, stale/replaced/cross-task records, missing
  acceptance checks, retained failure history, producer metadata not identity,
  output-shaped exit lines, finite Stop and cancellation priority.
- Knowledge: original hash observed independently, reliable duration bounds,
  transcript artifact, distinct source/external truth, high-risk evidence and
  non-actionable uncertainty, unsupported critic claims, canonical final set and
  stale text/link/card propagation, source write protection.
- Privacy: original command, error, prompt, subagent prompt, Cookie, Token,
  transcript and stdout/stderr are excluded from durable Hook events. Bindings
  contain local control references needed to authorize, not payload logs.

## Explicit non-claims

No measured line/branch coverage. No exhaustive interleaving or physical power-loss
test. No OS-enforced same-user trust separation. No complete shell side-effect
analysis. No guarantee of post-check path stability at actual host write time.
No native model identity attestation. No guaranteed factual truth or prevention of
all false natural-language statements. Stop is a bounded evaluator, not model truth
enforcement. No real image/video semantics or real Obsidian installation.

Every release report distinguishes implemented / locally tested / installed /
live desktop verified / blocked by host capability / not implemented.
