> Redacted historical observation: identifiers removed; originals remain private. Current behavior is defined by the v4 documentation.

# Host Result Classification Canary — Live Evidence 2026-09-08

## Main Conversation

Host conversation: `session-redacted`.

```text
pre_count: 10
post_count: 10
matched_count: 10
succeeded_count: 9
failed_count: 1
missing_post_count: 0
orphan_post_count: 0
```

Observed main tools:

```text
invoke_subagent
list_dir
manage_subagents
replace_file_content
run_command
view_file
write_to_file
```

Every observed Pre event had one matched Post event. The expected-failure
`run_command` record was:

```json
{
  "tool_name": "run_command",
  "outcome": "failed",
  "outcome_source": "step-output-exit-code",
  "error_present": false,
  "tool_result_observed": true,
  "process_exit_code_observed": 1
}
```

The user requested nested `exit 7`, but Antigravity normalized the observable
tool result to code 1. The Harness records the host-observed code and does not
claim the original nested code was preserved.

## Child Conversation

Child conversation: `session-redacted`.

The child produced one matched `view_file` Pre/Post pair. In this Canary the
parent `invoke_subagent` call also produced one matched Pre/Post pair, proving
both surfaces were visible. This does not yet prove a cryptographically trusted
parent-child identity binding because the relationship is not included in the
current Hook payload.

## File And Claim Truth

- The new TEMP file was first created during this Canary.
- The repository root did not contain a same-named file.
- Final content had `STATUS: reviewed`.
- Source fidelity was `supported`.
- External truth remained `not_verified`.
- Final disposition was `downgrade`.

The main agent additionally opened the child transcript to substantiate its
report. That was an extra `view_file` call and appears in the host ledger; the
claim that the report used only visible tool UI evidence was therefore too
broad.

## Privacy

Thirty matching event/correlation artifacts were scanned. None contained a raw
Windows path, conversation UUID, Canary output marker, source statement, or
Final Claim fields.

## Decision

Core observation is live verified for `list_dir`, `view_file`,
`write_to_file`, `replace_file_content`, `run_command`, `invoke_subagent`, and
`manage_subagents`. `multi_replace_file_content` was not exposed by this
desktop runtime and remains unavailable/unverified. General writes remain
observe-only rather than denied.
