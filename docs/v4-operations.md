# v4 operator guide

Use Windows PowerShell 5.1 (`powershell.exe`). The plugin wrappers launch that exact
runtime. PowerShell 7 JSON date conversion is not part of the current support claim.
Run commands from this source repository; installed scripts live under .gemini/scripts.
No project is automatically registered guarded by installation.

## Production scope

See `docs/production-readiness.md` for the scoped decision. Default observe is
development assistance, not guaranteed nonblocking execution or OS isolation.
Guarded is for supervised low-risk reversible native edits with external tests;
opaque terminal/subagent execution is blocked in protected contexts. Do not choose
guarded merely because a task is highly sensitive. No new business workspace has
been opted in during closeout.

## Start, authorize and resume

Minimal external PowerShell entry (replace the project and task values deliberately;
these commands are examples, not an instruction to opt in every project):

```powershell
$taskRoot = 'C:\path\to\your-project'
# Normal development: no Binding is needed for an unregistered/observe workspace.
& .\src\scripts\register-desktop-project.ps1 -ProjectRoot $taskRoot -Mode observe

# First creation of one explicitly selected low-risk guarded task:
$taskId = 'note-edit-001'
$state = Join-Path $taskRoot 'harness-state'
$task = & .\src\scripts\new-governed-task.ps1 -ProjectRoot $taskRoot -StateRoot $state `
  -LogicalTaskId $taskId -Objective 'Update the scoped internal note' `
  -AllowedPaths @('docs/note.md') -RequiredChecks @('note-format') | ConvertFrom-Json
if ($task.status -ne 'success') { throw 'Stop and inspect the existing task registration.' }
& .\src\scripts\new-attempt-record.ps1 -ProjectRoot $taskRoot -StateRoot $state `
  -TaskId $taskId -OperationId note-edit -AttemptId attempt-01
$ledger = Join-Path $state ('attempt-ledgers\' + $taskId + '.json')
& .\src\scripts\register-desktop-project.ps1 -ProjectRoot $taskRoot -Mode guarded
& .\src\scripts\new-desktop-session-binding.ps1 -ConversationId '<actual-host-UUID>' `
  -TaskRoot $taskRoot -ContractPath $task.contract -LedgerPath $ledger `
  -AttemptId attempt-01 -Role maker -ExpiresInMinutes 60
```

Do not rerun bootstrap to replace an existing task. Read its manifest and ledger,
then resume explicitly. Check every command's status before proceeding. The
`note-format` check is an example acceptance requirement: the real target project
must implement and execute its actual check; no test result is created by this guide.

1. Use the existing `new-governed-task.ps1` to preserve TaskRoot/intent continuity;
   create a canonical task Contract and record a running Attempt with existing
   `new-task-contract.ps1` / `new-attempt-record.ps1`.
2. Explicitly opt in the real task/project root:

```powershell
& .\src\scripts\register-desktop-project.ps1 -ProjectRoot '<task-root>' -Mode guarded
# strict returns unavailable and does not silently downgrade.
```

3. After the desktop supplies the actual conversation UUID, bind it externally:

```powershell
& .\src\scripts\new-desktop-session-binding.ps1 -ConversationId '<host-id>' `
  -TaskRoot '<task-root>' -ContractPath '<canonical-contract>' `
  -LedgerPath '<canonical-ledger>' -AttemptId '<running-attempt>' -Role maker `
  -ExpiresInMinutes 60
```

Binding is operator-script-unattested, not an independent identity. It can reference
a nested TaskRoot inside the registered project. Guarded native writes must be
within Contract and Binding scopes. Guarded opaque terminal/subagent calls are
unavailable; they are not silently executed through a substitute tool.

4. Renew/continue without changing the conversation or task identity:

```powershell
& .\src\scripts\new-desktop-session-binding.ps1 -ConversationId '<host-id>' `
  -Action Renew -ExpectedRevision 1 -AttemptId '<next-running-attempt>' `
  -AllowedPaths @('output.txt') -ExpiresInMinutes 60
```

Renew cannot widen permissions/change task/role/Contract or resurrect revoked
bindings. Earlier versions are retained. Close prior Attempts through the canonical
Attempt updater, preserve failure evidence, and explicitly reference any recovery.

## Inspect and complete

```powershell
& .\src\scripts\audit-desktop-hook-session.ps1 -ConversationId '<host-id>'
```

The audit is read-only and transcript-free. Empty/corrupt/pending evidence is not
success. Missing Post stays unresolved; opaque command completion stays unclassified
without trusted process evidence. Post does not close a Task Attempt.

Use the explicit canonical Completion Claim/Report/Envelope chain described in
`docs/v4-completion.md`, then the local Completion Gate. Never select the most recently
modified evidence or replace a rejected claim's history. Valid deterministic
evidence can reach checking, never verified without trusted external checker
authority. Missing/stale evidence remains unverified; the current acceptance
fixture's canonical completion chain is not closed.

Before ending any future Attempt, preserve immutable-by-convention evidence
snapshots under that task's private state and reference those exact files. Do not
point terminal evidence at output files that the next Attempt will edit. Use the
standard update-attempt-record.ps1 with a fixed EvidenceArtifact, actual observed
exit code only when available, and truthful passed/failed/stopped status. Rendered
reports project the ledger; rendering alone does not validate all evidence hashes.
The desktop acceptance operator helper is a fixture controller, not a general
production evidence lifecycle tool.

## Revoke, observe, disable and rollback

```powershell
& .\src\scripts\new-desktop-session-binding.ps1 -ConversationId '<host-id>' -Action Revoke
& .\src\scripts\register-desktop-project.ps1 -ProjectRoot '<task-root>' -Mode observe
& .\deploy\install-desktop-hook-plugin.ps1 -Mode Diagnose
& .\deploy\install-desktop-hook-plugin.ps1 -Mode Disable
& .\deploy\install-desktop-hook-plugin.ps1 -RollbackManifest '<explicit-plugin-manifest>'
& .\deploy\sync-to-runtime.ps1 -RollbackManifest '<explicit-runtime-manifest>'
```

Disable preserves the plugin in a recoverable transaction. Host configuration may
be cached; user cancellation/emergency disable takes precedence over any local
Stop evaluator. No automatic model loop is installed. Roll back both matching
runtime and plugin transactions for release-level recovery, using recorded explicit
paths from docs/v4-release.md; never choose a backup by latest modification time.
Unknown/corrupt manifest or changed current files require operator review.

## State capacity, privacy and recovery

Hook stdin: 1 MiB and 1.5-second read timeout; JSON state: max 4 MiB; lock contention:
750 ms; callbacks: max 128 per operation. Host hook timeout remains 10 seconds.
No repository/whole-disk scan or per-hook repository rehash; only referenced
Contract/Ledger/Binding, target ancestry and the current operation are checked.
Observe read tools may continue on journaling failure; mutation/opaque tools deny
on journaling failure to avoid unrecorded duplicate admission.

Current operation JSON is atomically replaced; prior versions and interrupted
pending files remain. These files are NOT immutable or signed. Audit never repairs
history automatically. A pending atomic commit requires operator inspection of the
specific operation; absence of committed Post stays unresolved. To resume work use
a recorded next Attempt, not new TaskRoot/ID to conceal prior outcomes.

There is no automatic retention deletion or total-state quota enforcement. Capacity
can grow with history; inspect harness-state size during maintenance and move only
explicitly selected closed-session directories into an operator-owned archive.
Keep failure/deny/claim/gate records. Do not empty archives automatically.
