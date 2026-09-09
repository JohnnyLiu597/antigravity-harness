> Redacted historical observation: identifiers removed; originals remain private. Current behavior is defined by the v4 documentation.

# Core Tool Observation Canary — Live Findings 2026-09-08

## Scope

The v3.3 Canary exercised list, view, write, replace, command, subagent, and
subagent-management behavior against one TEMP file. The user ran the scenario
in two desktop conversations; the later conversation produced the reported
final response.

## Latest Main Conversation

Host conversation: `session-redacted`.

Session audit before v3.4:

```text
pre_count: 9
post_count: 8
matched_count: 8
missing_post_count: 1
orphan_post_count: 0
observed_tools:
  list_dir
  manage_subagents
  replace_file_content
  run_command
  view_file
  write_to_file
```

The missing Post corresponds to the first `write_to_file` call rejected by
host parameter validation after PreToolUse. This is correctly visible as an
unclosed Pre event.

`multi_replace_file_content` was not exposed by the current desktop tool
schema, so no call occurred. The parent `invoke_subagent` call also produced no
Hook event even though the tool ran. Therefore parent-side subagent invocation
coverage remains unverified for this desktop build.

## Child Conversation

The child conversation `session-redacted` produced a
matched `view_file` Pre/Post pair. This proves that child activity can produce
its own host events, but the current evidence does not cryptographically bind
the parent invocation to that child identity.

## Command Outcome Defect

The expected-failure command requested exit 7. Antigravity's step output
reported:

```text
The command exited with code 1.
```

PostToolUse supplied an empty `error` field, so v3.3 incorrectly classified
the call as succeeded. This shows that Hook `error` represents Hook/tool-layer
failure, not necessarily the nested process result.

v3.4 reads the fixed host step output path in memory, stores only its SHA-256,
and parses the observed tool result code. Raw output is never persisted.

## Workspace And Claim Truth

- The TEMP file exists and contains the expected source statement and reviewed
  status.
- No same-named file exists in the repository root.
- Source fidelity was correctly reported as supported.
- External truth was correctly kept at not_verified.
- The Final Claim Set downgraded the deliberately unsupported general claim.

## Remaining Boundaries

- Expanded tool coverage remains partial until every declared tool is observed
  in a fresh session.
- Pre without Post must remain a warning, not be guessed as success or failure.
- Parent `invoke_subagent` and child conversation identity are not yet bound.
- Domain-specific correctness remains the responsibility of the target
  project's deterministic Gate.
