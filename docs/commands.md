# Commands & Operational Guide

## v4 current entrypoints

Use Windows PowerShell 5.1. The current operator workflow is
`docs/v4-operations.md`, explicit completion chain is `docs/v4-completion.md`,
and transactional recovery is `docs/v4-deployment.md`.
Run all release checks with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/test-v4-release.ps1`.
`-NoBackup` is now refused; normal/runtime plugin transactions are both retained.
The commands below document pre-v4 helpers; do not use their old newest-evidence
or Canary assumptions as current authorization policy.

This document lists the PowerShell commands and workflows used to manage, verify, deploy, and audit `antigravity-harness`.

---

## 1. Deployment & Synchronization

### Install The Antigravity Desktop Hook Probe

```powershell
.\deploy\install-desktop-hook-plugin.ps1 -DryRun
.\deploy\install-desktop-hook-plugin.ps1
.\deploy\install-desktop-hook-plugin.ps1 -Mode Disable
.\deploy\install-desktop-hook-plugin.ps1 -Mode Enable
```

The transaction manifest returned by installation can be passed back with
`-RollbackManifest`. This installer never edits Antigravity.exe, `config.json`,
or unrelated plugins.

Audit one desktop conversation's privacy-bounded Hook coverage:

```powershell
.\src\scripts\audit-desktop-hook-session.ps1 `
  -ConversationId "<conversation-id>" `
  -ExpectedTools @("view_file", "write_to_file", "invoke_subagent")
```

### Deploy Source Payload to Runtime (`sync-to-runtime.ps1`)

Deploys clean assets from `src/` to `$env:USERPROFILE\.gemini` using a transactional, two-phase backup pipeline:

```powershell
# Preview changes without modifying disk
.\deploy\sync-to-runtime.ps1 -DryRun

# Standard deployment (creates timestamped backup in runtime)
.\deploy\sync-to-runtime.ps1

# Backups are mandatory in v4, including isolated tests.

# Revert a previous sync transaction using its manifest
.\deploy\sync-to-runtime.ps1 -RollbackManifest "~\.gemini\backup-20260903-120000-abcd1234-antigravity-harness-sync\sync-transaction.json"
```

### Import Runtime Assets Back to Source (`sync-from-runtime.ps1`)

Imports live modifications and newly created skills from `$env:USERPROFILE\.gemini` back into `src/`:

```powershell
# Standard incremental import (skips private skills and runtime state)
.\deploy\sync-from-runtime.ps1

# Full refresh (archives current src/ to artifacts/ before importing)
.\deploy\sync-from-runtime.ps1 -Refresh
```

---

## 2. Verification & Testing

### Package Integrity & Security Check (`verify-package.ps1`)

Performs static analysis, secret/path leak scanning, PSParser AST verification, and JSON validation:

```powershell
# Run package verification against current repository root
.\deploy\verify-package.ps1
```

### Sync Boundaries Integration Test (`test-sync-boundaries.ps1`)

Tests bidirectional isolation in an isolated `$env:TEMP` scratch environment:

```powershell
# Run automated sync boundary assertions
.\deploy\test-sync-boundaries.ps1
```

### Multi-Tier Verification Gate (`invoke-verification-gate.ps1`)

Executes the full ladder of checks (syntax, JSON, context budget, package verification, and boundary tests):

```powershell
# Run all verification gate checks
.\src\scripts\invoke-verification-gate.ps1

# Quick run (skip slow boundary integration test)
.\src\scripts\invoke-verification-gate.ps1 -SkipBoundaries
```

The v2 gate also runs manifest integrity and the deterministic behavioral eval
owner through package verification and `src\harness-evals\run-harness-evals.ps1`.

### Truth And Native Surface Probes

```powershell
.\src\scripts\verify-manifest-integrity.ps1
.\src\scripts\audit-harness-components.ps1
.\src\scripts\probe-native-surfaces.ps1
```

The static native-surface probe never marks in-app tools available without live
evidence.

### Bounded Execution

```powershell
.\src\scripts\new-task-contract.ps1
.\src\scripts\new-governed-task.ps1
.\src\scripts\test-task-scope.ps1
.\src\scripts\new-job-state.ps1
.\src\scripts\update-job-state.ps1
.\src\scripts\get-workspace-fingerprint.ps1
.\src\scripts\invoke-safe-command.ps1
```

### Causal Verification

```powershell
.\src\scripts\detect-project-test-surface.ps1
.\src\scripts\invoke-verification-envelope.ps1
.\src\scripts\new-completion-claim.ps1
.\src\scripts\invoke-completion-gate.ps1
.\src\harness-evals\run-harness-evals.ps1
```

### Attempt Ledger And Deterministic Reporting

```powershell
.\src\scripts\new-attempt-record.ps1
.\src\scripts\update-attempt-record.ps1
.\src\scripts\render-completion-report.ps1
.\src\harness-evals\test-attempt-ledger.ps1
```

Final reports must be generated from the ledger rather than reconstructed from
chat history.

Use observed v2.2 inputs:

```powershell
.\src\scripts\test-task-scope.ps1 -ContractPath "<contract>" -ObserveWorkspace
.\src\scripts\new-attempt-record.ps1 -ProjectRoot . -InputPaths @("src/file.ps1") `
  -TaskId "task-id" -OperationId "operation-id"
```

Without `-ObserveWorkspace`, scope output is labelled `pre_write_declared`.
With it, output is labelled `post_write_observed`; this is an after-the-write
audit, not proof that the host intercepted the write beforehand.

Verification tests should write structured results:

```json
{"schema":"antigravity-test-result-v1","cases":[{"id":"case-id","status":"passed"}]}
```

Audit whether a task actually used the canonical governance chain:

```powershell
.\src\scripts\audit-governed-execution.ps1 -TaskRoot "<isolated-task-root>" -DecisionPath "<explicit-decision>"
```

---

## 3. Context & Project Scaffolding

### Audit Context Budget (`audit-context-budget.ps1`)

Measures line and byte counts across rules, anchors, skills, and agent definitions:

```powershell
# Audit current workspace context footprint
.\src\scripts\audit-context-budget.ps1
```

### Scaffold New Target Project (`init-project-harness.ps1`)

Initializes an Antigravity Harness in any target repository:

```powershell
# Scaffold current directory with mission.md, CONTEXT.md, MEMORY.md, and .agent/rules.md
.\src\scripts\init-project-harness.ps1

# Scaffold a specific project with custom name and goal
.\src\scripts\init-project-harness.ps1 -Root "C:\path\to\my-project" -ProjectName "MyProject" -PrimaryGoal "Deliver core API services"
```

### Ingest Learning / Incident Record (`new-learning-intake.ps1`)

Records a bug, tool loop, or review miss into structured learning traces:

```powershell
.\src\scripts\new-learning-intake.ps1 `
    -Name "ps-regex-word-boundary" `
    -Source "test" `
    -Route "rule" `
    -Summary "Fixed regex false positive on sk- prefix in English text" `
    -FailureMode "Regex pattern matched normal English words" `
    -Evidence @("tester.md L25", "agent-rules.template.md L69") `
    -NextActions @("Use lookbehind (?<![a-zA-Z]) for key patterns")
```
# Asymmetric collaboration commands (2026-09-10)

Use `src/scripts/invoke-antigravity-handoff.ps1` for shared Init/Acquire/Status/
RecordEvidence/Release/Handoff. Handoff requires the existing logical TaskId,
`-NativeTaskRoot` and exact `-DecisionPath` and reruns the existing governed audit.
Missing/stale native evidence blocks exchange; Release can stop without passing.
Run `deploy/test-v4-release.ps1` for full source regression. The original suites
remain; modern-skill and strict/shared-handoff suites are added. Skills are
installed from one source into both `skills` and `config/skills`; private markers
and divergent-import refusal remain binding. No native Stop activation is added.
