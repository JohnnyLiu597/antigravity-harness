# v3.5 Session, Task, And Attempt Binding

## Purpose

v3.5 tests whether a host-issued Antigravity conversation identity can be
required to reference a real governed TaskRoot, Contract, Attempt Ledger, and
running Attempt before a bounded write proceeds.

The first deployment applies only to:

```text
$env:TEMP\antigravity-v351-binding-task-case-02\
```

Writes elsewhere remain observe-only. This prevents an experimental binding
error from locking normal projects.

## Registration

An external operator registers a session after the desktop conversation UUID
is known:

```powershell
.\src\scripts\new-desktop-session-binding.ps1 `
  -ConversationId "<host conversation UUID>" `
  -TaskRoot "<Canary TaskRoot>" `
  -ContractPath "<canonical Contract>" `
  -LedgerPath "<canonical Attempt Ledger>" `
  -AttemptId "<running Attempt>" `
  -Role maker
```

The script validates that Contract and Ledger are inside TaskRoot, refer to the
same task and project, and contain exactly one running Attempt. The private
binding record contains local paths needed for subsequent validation. Hook
events expose only hashes of TaskRoot, TaskId, and AttemptId.

## PreToolUse Decision

For write/edit tools targeting the exact Canary root:

```text
binding missing             -> deny
binding invalid             -> deny
Attempt not running         -> deny
non-writer role             -> deny
target outside TaskRoot     -> deny
target outside Contract     -> deny
active valid binding        -> allow
```

The pre-existing exact Sentinel deny takes precedence. Unrelated writes remain
observe-only allow.

## Authority Boundary

The host conversation ID is not model-selected, but the local binding record is
not a trusted cryptographic attestation. A model with unrestricted filesystem
and terminal permissions may still attempt to inspect or alter private state.
Therefore v3.5 proves conditional host admission, not trusted Reviewer identity.

The first live Canary showed that `force_ask` was recorded but not presented or
enforced by the tested desktop host; the unbound file was created. v3.5.1 uses
hard deny for invalid admission. Human authority is exercised by externally
registering a validated binding before retrying in the same conversation.

## Installed Canary Record

```text
normal_runtime_transaction: 62f00c7eafc34b09b9706c120616c0a8
normal_runtime_files: 65/65
normal_runtime_fingerprint: 65ea9e1a17c3b43c18ba3a490d72b7ee3e0c51503dd27af9dfdd51914c1426d6
desktop_plugin_files: 6/6
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260908-212940882-antigravity-reliable-control\install-transaction.json
canary_task_root:
  $env:TEMP\antigravity-v35-binding-task-case-01
canary_contract:
  harness-state\contracts\antigravity-v35-binding-canary-case-01.json
canary_ledger:
  harness-state\attempt-ledgers\antigravity-v35-binding-canary-case-01.json
canary_attempt: binding-attempt-01
canary_attempt_state: running
canary_output_exists: false
installed_unbound_decision: force_ask
installed_unbound_side_effect: false
live_desktop_binding: unverified
```

The v3.5 live result invalidated the force-ask assumptions in that record.
case-01 is preserved and closed as a failed Attempt with its `output.txt` side
effect. The replacement v3.5.1 record is:

```text
normal_runtime_transaction: 42756aff7fc84ab5b6a90ac00dc6a17a
normal_runtime_files: 65/65
normal_runtime_fingerprint: 0f2ba07752ca34072eb299416dbcfbb1c49bca3fe9913856e8d43903c5bf4cd3
desktop_plugin_files: 6/6
desktop_plugin_transaction:
  $env:USERPROFILE\.gemini\config\plugin-backups\20260908-231335004-antigravity-reliable-control\install-transaction.json
canary_task_root:
  $env:TEMP\antigravity-v351-binding-task-case-02
canary_contract:
  harness-state\contracts\antigravity-v351-binding-canary-case-02.json
canary_ledger:
  harness-state\attempt-ledgers\antigravity-v351-binding-canary-case-02.json
canary_attempt: binding-deny-attempt-01
canary_attempt_state: running
canary_output_exists: false
installed_unbound_decision: deny
installed_unbound_side_effect: false
live_desktop_binding: unverified
```
