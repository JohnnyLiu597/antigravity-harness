# Job State And Recovery

Job records mirror Antigravity work; they do not implement another scheduler.

```text
drafted -> approved -> running -> checking -> waiting_approval
                                      \-> verified | blocked | stopped
```

Every record contains a stable job ID, a new attempt ID for each retry, a stable
idempotency key only for retries of the same logical effect, task-contract
reference, budgets, isolation, current state, last verified commit or workspace
fingerprint, evidence artifacts, blocker, stop reason, and one next action.

Transitions are monotonic within one attempt. Reopening completed work requires
a new attempt. Resume reads the job record and task contract before using chat
history. Accepted work is reused only while its input hashes and verification
evidence still match.

Runtime-private records live under:

```text
$env:USERPROFILE\.gemini\harness-state\jobs\
```

The `harness-state` directory contains a `.gemini-private` marker file and is
excluded from both source synchronization directions.

Each material operation also creates an Attempt Ledger entry under
`attempt-ledgers\`. Job state answers where the task is; Attempt Ledger answers
what was tried, what failed, what side effects were observed, how recovery
changed the next attempt, and whether the final result is `passed_after_retry`.
