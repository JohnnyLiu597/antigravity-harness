> Redacted historical observation: identifiers removed; originals remain private. Current behavior is defined by the v4 documentation.

# Session Binding Force-Ask Failure — Live Evidence 2026-09-08

## Expected

An unbound `write_to_file` targeting the v3.5 Canary TaskRoot should return
`force_ask`, display an uncached user confirmation, and remain unexecuted after
the user denies it.

## Observed

Host conversation: `session-redacted`.

PreToolUse correctly recorded:

```text
decision: force_ask
reason_code: session-binding-missing
binding_status: missing
```

No confirmation was displayed and no user choice occurred. PostToolUse then
recorded a matched successful `write_to_file`, and `output.txt` was created.
No session binding existed.

## Decision

`force_ask` is not a reliable enforcement boundary in the tested Antigravity
Desktop environment. Cached or host permission behavior may explain the result,
but the observed side effect is sufficient to reject the mechanism.

v3.5.1 changes missing, invalid, stale, non-writer, and out-of-scope Canary
bindings to `deny`. Human authorization is expressed by externally creating a
validated binding before the next call, not by relying on an inline prompt.
