# v3.3 Core Tool Observation

## Motivation

A real multimodal knowledge-ingestion audit showed that the v3.2 Hook was
active but observed only `list_dir|run_command`. The task's most important
actions used `view_file`, write/edit tools, and `invoke_subagent`, so the host
ledger could not prove which originals were opened, which outputs were edited,
or whether subagent and file-operation failures were omitted.

The same audit found broader truth problems that apply beyond knowledge bases:

- reopening a source proves source fidelity, not external truth;
- copied expected hashes are not independent observations;
- high-confidence or complete-coverage labels need artifacts;
- critic downgrades must propagate through a Final Claim Set instead of being
  appended after unchanged conclusions.

## Bounded Core Matcher

v3.3 observes:

```text
list_dir
view_file
write_to_file
replace_file_content
multi_replace_file_content
run_command
invoke_subagent
manage_subagents
```

All newly added tools remain `allow` and observe-only. The only deny rule is
the previously verified exact v3.1 Sentinel Token.

## Safe Metadata

PreToolUse records host conversation and step hashes, tool name, full argument
hash, hashes of known top-level target paths, target count, requested subagent
count, and decision. PostToolUse records matched/orphan status,
success/failure, and error hash.

Raw paths, prompts, subagent prompts, file contents, commands, errors,
transcripts, and tool output are never persisted.

## Session Coverage Audit

```powershell
.\src\scripts\audit-desktop-hook-session.ps1 `
  -ConversationId "<host conversation UUID>" `
  -ExpectedTools @("view_file", "write_to_file", "invoke_subagent")
```

The audit reports Pre/Post counts, matched success and failure counts, denials,
missing Post, orphan Post, expected-tool coverage, and per-tool counts. It
hashes the supplied conversation ID and never opens a transcript.

This is an execution coverage audit, not a content or correctness grader.
Project-specific media duration, Wiki Link, financial-language, or knowledge
card checks belong in the target project's local deterministic Gate.

## Truth Boundary

Static tests prove the expanded matcher, target hashing, subagent count,
correlation, and audit logic. Real desktop coverage remains unverified until a
fresh conversation invokes the selected tools and the audit finds complete
Pre/Post pairs.

The first live Canary found one parameter-validation Pre event without Post,
no parent `invoke_subagent` Hook event, and an empty Post `error` for a failed
run command. v3.4 therefore parses the numeric code from the host's fixed step
output while storing only the output hash. See
`docs/live-core-tool-observation-20260908.md`.

## v3.4 Installed Record

```text
normal_runtime_transaction: e43de8c887684fd0815bdbf5614bb7f9
normal_runtime_files: 64/64
normal_runtime_fingerprint: 84fd4ea6b6511d9d155c3810796715e966dec370f17873e08e5285f801e9039d
desktop_plugin_files: 6/6
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260908-042557938-antigravity-reliable-control\install-transaction.json
installed_observed_process_code: 1
installed_outcome: failed
installed_outcome_source: step-output-exit-code
installed_raw_output_leak: false
live_corrected_classification: unverified
```

The next restarted Canary live-verified corrected result classification and
the expanded available-tool subset. Runtime evidence was refreshed through:

```text
normal_runtime_transaction: fce65119918648ceb0335a17b9491dc3
normal_runtime_fingerprint: 839fbfbe4b6cdfce767453f631500593ab72d9c0fbc9314869e2b2a9e4376e3c
```

The next restarted Canary produced complete 10/10 main-session pairing,
including parent `invoke_subagent`, and one matched child `view_file` pair. The
failed command was correctly classified from host-observed code 1. See
`docs/live-host-result-classification-20260908.md`.

## Installed Record

```text
normal_runtime_transaction: e3a1f51d5b2b470e90a5c995f22654a4
normal_runtime_files: 64/64
normal_runtime_fingerprint: b98d35485f6a336c808fcad03a494b44a8c5fd28ed067dcc6e253e5aa1222022
desktop_plugin_files: 6/6
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260907-172952633-antigravity-reliable-control\install-transaction.json
installed_view_file_pre_post: matched/succeeded
installed_target_path_count: 1
installed_raw_path_leak: false
live_desktop_core_coverage: unverified
```
