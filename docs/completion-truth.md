# Completion Truth Model

Antigravity may propose progress, but only deterministic evidence may close a
task. The harness distinguishes these states:

| State | Meaning | Authority |
|---|---|---|
| `planned` | Work is described but not attempted. | maker |
| `attempted` | An action was requested. | maker |
| `executed` | A tool call returned; the target outcome is not proven. | maker |
| `partial` | Some acceptance conditions have evidence. | maker |
| `passed` | One bounded deterministic check passed. | checker/tool |
| `checking` | Completion evidence is being evaluated. | gate |
| `unverified` | Required evidence is absent, stale, or incomplete. | gate |
| `blocked` | Progress requires user input or an external state change. | any role |
| `verified` | Every required condition has current evidence and trusted external checker attestation. | attested completion gate only |
| `approved` | A named high-risk effect is authorized. | user only |

`success` from a tool means the invocation returned successfully. It never
means the user-visible objective is complete. Verification becomes stale when
the checked source, tests, grader, evidence, environment, or protected paths no
longer match the envelope.

The current source-only gate returns `checking` after deterministic evidence
passes because reviewer identity is not externally attested. It must not turn a
self-reported role into `verified`.

Completion arbitration also validates a private Attempt Ledger and its
deterministically rendered report. If the report omits, changes, or miscounts a
failed/rejected attempt, the gate returns `unverified` with
`attempt-report-mismatch`.

The final response must list verified claims separately from partial,
unverified, blocked, and deferred work. Missing evidence fails closed.
