# Release & Deployment Lifecycle Guide

This guide describes the release process, version verification gates, and deployment lifecycle for `antigravity-harness`.

---

## 1. Release Lifecycle Overview

The release cycle guarantees that changes made in the versioned source repository (`src/`) are safe, verified, and reversible before being deployed to the local runtime (`~/.gemini`):

```
┌─────────────────┐     1. Static Gates      ┌─────────────────────┐
│  Source Changes │─────────────────────────►│  verify-package.ps1 │
└─────────────────┘                          └──────────┬──────────┘
                                                        │ PASS
                                                        ▼
┌─────────────────┐     2. Boundary Tests    ┌─────────────────────┐
│ Deploy Approved │◄─────────────────────────┤test-sync-boundaries │
└────────┬────────┘                          └─────────────────────┘
         │
         │ 3. DryRun Preview
         ▼
┌─────────────────────────────────┐
│ sync-to-runtime.ps1 -DryRun     │
└────────┬────────────────────────┘
         │
         │ 4. Transactional Install
         ▼
┌─────────────────────────────────┐
│ sync-to-runtime.ps1             │
│ (Atomic SHA256 + Rollback Log)  │
└─────────────────────────────────┘
```

---

## 2. Pre-Release Verification Gates

Before publishing or installing a release, the complete source verification
gate must pass:

```powershell
.\src\scripts\invoke-verification-gate.ps1
```

### Gate 1: Package Integrity & Leak Scanning
```powershell
.\deploy\verify-package.ps1
```
- Ensures all mandatory files (`AGENTS.md`, `GEMINI.md`, `harness.capabilities.json`, `harness.components.json`, skills, agents, docs) exist.
- Validates that `src/AGENTS.md` is strictly under 80 lines.
- Scans `src/` recursively for forbidden runtime state, local user filepaths, personal usernames, and API keys.
- Tokenizes all PowerShell scripts and parses all JSON files.

### Gate 2: Sync Boundaries Integration Testing
```powershell
.\deploy\test-sync-boundaries.ps1
```
- Tests bidirectional isolation inside an isolated `$env:TEMP` scratch workspace.
- Asserts that `.gemini-private` markers protect runtime assets from being overwritten.
- Asserts that private files (`config.json`, `brain/`, `conversations/`) are blocked in both sync directions.

### Gate 3: Context Budget Audit
```powershell
.\src\scripts\audit-context-budget.ps1
```
- Verifies line and byte limits across all context anchors, skills, and agents.

### Gate 4: Manifest Truth And Behavioral Regressions

```powershell
.\src\scripts\verify-manifest-integrity.ps1
.\src\harness-evals\run-harness-evals.ps1
```

- Rejects phantom scripts, unsupported verified claims, and expired components.
- Proves scope, state, idempotency, real exit, timeout, stale verification,
  maker-checker, and completion-gate behavior.

---

## 3. Transactional Deployment & Rollback

### Two-Phase Installation
When `sync-to-runtime.ps1` executes without `-NoBackup`:
1. **Pre-Copy Backup**: Every existing file in `$env:USERPROFILE\.gemini` that would be overwritten is backed up to a timestamped folder:
   `~/.gemini/backup-{stamp}-{guid}-antigravity-harness-sync/`
2. **Atomic Verification**: Source and installed file SHA256 hashes are verified.
3. **Auto-Rollback on Error**: If any copy fails or a hash mismatch is detected, the transaction automatically restores backed-up files and deletes newly created entries.

### Manual Rollback
If an installed release causes unexpected issues in the live runtime:
```powershell
.\deploy\sync-to-runtime.ps1 -RollbackManifest "~\.gemini\backup-YYYYMMDD-HHMMSS-GUID-antigravity-harness-sync\sync-transaction.json"
```

---

## 4. Release Checklist

- [ ] All new skills have `SKILL.md` starting with `---` (UTF-8 without BOM).
- [ ] `src/AGENTS.md` remains under 80 lines.
- [ ] No references to old or deprecated Gemini models in `src/GEMINI.md`.
- [ ] Native surfaces and model routing are not marked available without live evidence.
- [ ] Manifest integrity and all behavioral regressions pass.
- [ ] Every verified completion claim matches the current workspace fingerprint.
- [ ] `deploy/verify-package.ps1` returns `passed`.
- [ ] `deploy/test-sync-boundaries.ps1` returns `success`.
- [ ] `deploy/sync-to-runtime.ps1 -DryRun` confirms expected file counts and zero leaks.
- [ ] Git commit created with clean summary.
- [ ] Runtime install, merge, deployment, and publication have explicit user approval.
