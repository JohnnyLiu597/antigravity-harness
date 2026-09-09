# v3.0 Antigravity Desktop Hook Probe

## Purpose

The v3 line moves governance admission from model-selected script calls toward
Antigravity Desktop's documented execution-loop Hooks. The first release is an
observe-only Probe, not a mutation gate.

## Current Probe

The plugin source is:

```text
src/desktop-hooks/antigravity-reliable-control/
  plugin.json
  hooks.json
  hooks/pre-tool-use.cmd
  hooks/pre-tool-use.ps1
```

It registers one `PreToolUse` matcher for `list_dir`. The handler receives JSON
on stdin, records bounded host metadata, and always returns `decision=allow`.
Malformed input, logging failure, and unavailable state paths also fail open.

The Probe stores only:

- event type and UTC time;
- SHA-256 of the host-provided conversation ID;
- step index and tool name;
- SHA-256 of tool arguments;
- SHA-256 of workspace paths and workspace count;
- `observe-only-fail-open` enforcement state.

It never stores raw prompts, transcripts, tool arguments, workspace paths,
commands, credentials, or tool output. Runtime events live under:

```text
$env:USERPROFILE\.gemini\harness-state\hook-probe\
```

The directory contains `.gemini-private`.

## Installation

```powershell
.\deploy\install-desktop-hook-plugin.ps1 -DryRun
.\deploy\install-desktop-hook-plugin.ps1
```

The desktop plugin target is:

```text
$env:USERPROFILE\.gemini\config\plugins\antigravity-reliable-control\
```

Disable or re-enable the Probe without deleting it:

```powershell
.\deploy\install-desktop-hook-plugin.ps1 -Mode Disable
.\deploy\install-desktop-hook-plugin.ps1 -Mode Enable
```

Rollback uses the transaction manifest returned by installation. A displaced
plugin is moved to the recoverable `config/plugin-trash/` directory.

## Truth Boundary

Static tests prove handler behavior and installed-file hashes. They do not
prove that the running desktop application loaded the plugin. Until a fresh
Antigravity Desktop conversation invokes `list_dir` and produces a new event,
availability and enforcement remain `unverified`.

After live observation, the Probe may be classified as host-observed but still
does not enforce mutation scope. `write_to_file`, edit tools, `run_command`,
subagents, and `Stop` remain outside v3.0 Probe enforcement.

## Promotion Order

1. Observe `list_dir` in a fresh restarted desktop session.
2. Prove a benign sentinel `deny` blocks its side effect.
3. Add write-ahead PreToolUse and correlated PostToolUse event records.
4. Bind host conversation IDs to immutable task and role assignments.
5. Add mutation scope enforcement.
6. Add a bounded Stop completion gate with loop protection.

No later stage is enabled merely because an earlier static test passes.

## Installed Probe Record

```text
normal_runtime_transaction: 61bf4d33baec47d4b1eb90cad203fec7
normal_runtime_files: 63/63
normal_runtime_fingerprint: 6bf186b8f153174e69988ef433df5918de2ba6239849fc13260d63b4f057afbd
desktop_plugin_files: 4/4
desktop_plugin_enabled: true
desktop_plugin_hash_mismatches: 0
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260906-014403934-antigravity-reliable-control\install-transaction.json
installed_gate: passed
live_desktop_event: passed
live_event_sha256: ce768e98785ec20cfef3710a395a413818a1c160bea914c37e15e1eb7953d2cc
```

The first restarted desktop Canary produced a real `PreToolUse` event for
`list_dir` with host step index 2. See `docs/live-hook-probe-20260906.md`.
This promotes Probe availability only; mutation denial and Stop enforcement
remain disabled and unverified.

## v3.1 Exact Sentinel Deny

The next bounded stage extends the matcher to `list_dir|run_command`. Ordinary
`run_command` calls remain `allow`. A command is denied only when its
`CommandLine` contains the exact, case-sensitive token:

```text
ANTIGRAVITY_HOOK_DENY_SENTINEL_V1
```

The handler records only the argument hash, decision, and reason code; it does
not persist the token or command. Malformed hook input and logging failures for
ordinary calls remain fail-open. After valid input identifies the exact
sentinel, the decision remains `deny` even if event logging fails.

Static regression tests prove the decision function. Live side-effect
prevention remains unverified until a restarted desktop session proposes a
sentinel command whose target file is independently confirmed absent.

Installed v3.1 record:

```text
normal_runtime_transaction: 4ea1426efcaf4ca9882fe5676b6e46ec
normal_runtime_files: 63/63
normal_runtime_fingerprint: 78214fccfc06b04ed079a9ede13885af2b7765307d3d6d7052692fc6a3dc6672
desktop_plugin_files: 4/4
desktop_plugin_hash_mismatches: 0
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260906-164359681-antigravity-reliable-control\install-transaction.json
installed_wrapper_normal_command: allow
installed_wrapper_exact_sentinel: deny
live_desktop_side_effect_prevention: unverified
```

The restarted desktop Canary subsequently proved the exact sentinel denial:
the normal command was allowed, the sentinel command was denied at host step 4,
and its target file remained absent. See
`docs/live-sentinel-deny-20260906.md`. This promotes only the exact-token
capability; general mutation gates remain disabled.

Live-evidence runtime refresh:

```text
normal_runtime_transaction: ce6f22951be742a3accecdcef1bc3cc8
normal_runtime_fingerprint: 8ebc808a8bc50cbebe5ea95cbe83a4bdcd44534ad6b30c56ca0c3db81d3ee1c8
```

## v3.2 Pre/Post Correlation

For allowed `list_dir|run_command` calls, PreToolUse now writes an immutable
correlation record keyed by:

```text
SHA256(conversation_id_sha256 + "|" + stepIdx)
```

PostToolUse independently recomputes the key, reads the Pre record, and writes
a separate completion record. It records `succeeded` for an empty host error
and `failed` for a non-empty host error. Raw errors are never stored; only
`error_present` and `error_sha256` are retained.

Missing Pre records are explicit `orphan` Post events rather than silently
discarded. Malformed Post input and logging failures always return `{}` so the
observational hook cannot break the desktop loop. Exact PreToolUse sentinel
denials remain terminal at Pre and do not require Post correlation.

Static tests cover matched success, matched failure, orphan Post, malformed
input, privacy, and Windows wrapper behavior. Live desktop Pre/Post pairing is
unverified until a restarted session runs one zero-exit and one nonzero-exit
command.

Installed v3.2 record:

```text
normal_runtime_transaction: c8f6758f364044f0b68e803e77c315c8
normal_runtime_files: 63/63
normal_runtime_fingerprint: 0735f57ebc7ae8ddfe3a21680654f73ae121a1bcdca10818f9312f5304027e42
desktop_plugin_files: 6/6
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260906-172420248-antigravity-reliable-control\install-transaction.json
installed_pre_wrapper: allow
installed_post_wrapper: {}
installed_correlation: matched/failed
installed_raw_error_leak: false
live_desktop_pre_post_pairing: unverified
```
