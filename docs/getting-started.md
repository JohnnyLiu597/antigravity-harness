# Getting Started with Antigravity Harness

> Script-concept guide. For current Desktop operation and actual enforcement
> limits use v4-operations.md and production-readiness.md. CLI helpers, role
> labels and source-level checks do not prove native activation or checker identity.

The `antigravity-harness` is a versioned, maintainable agent governance and reliability control plane designed for Google Antigravity and Gemini CLI.

It keeps agents productive as makers while externalizing scope bounds, execution state, causal verification, and user approval authority.

---

## Core Concepts

1. **Task Contract**:
   A declarative schema (`antigravity-harness-task-contract-v2`) that locks down objective, non-goals, allowed write paths, change budgets (file and line caps), and approval triggers prior to any modification.

2. **Scope Guard**:
   A script-enforced-on-invocation boundary evaluated via `test-task-scope.ps1`. In observed mode it derives changed paths and added lines from the Task Contract baseline instead of trusting caller-supplied counts.

3. **Attempt Ledger**:
   An append-only state store (`antigravity-harness-attempt-ledger-v1`) under `$env:USERPROFILE\.gemini\harness-state\attempt-ledgers\`. The containing state root has a `.gemini-private` marker file. Scripts derive input hashes, workspace changes, and observed side effects, preserve failures and recovery actions, and compute `passed_after_retry`.

4. **Verification Envelope**:
   A deterministic test executor (`invoke-verification-envelope.ps1`). It executes verification commands with finite timeouts, verifies AST binding, detects test collection counts, and compares before/after workspace fingerprints.

5. **Completion Gate**:
   A deterministic source-only arbiter (`invoke-completion-gate.ps1`). It prevents maker self-verification, matches claim hashes against envelope and ledger records, and holds status at `checking` unless an external trusted checker authority attestation exists. It does not prove reviewer identity by itself.

---

## Standard Workflow

### 1. Initialize Task Contract
Create a contract locking your objective and file bounds:
```powershell
powershell.exe -NoProfile -Command "& .\src\scripts\new-task-contract.ps1 -ContractId 'task-feature-01' -Objective 'Implement feature' -AllowedPaths 'docs/feature.md' -MaxFiles 1 -MaxAddedLines 100"
```

### 2. Pre-tool Scope Validation
Before writing files, verify scope compliance. Prefer baseline observation over
caller-declared file and line counts:
```powershell
powershell.exe -NoProfile -Command "& .\src\scripts\test-task-scope.ps1 -ContractPath '<path-to-contract>' -ObserveWorkspace"
```

### 3. Record Attempts in Ledger
Track each material operation:
- Create an attempt via `new-attempt-record.ps1` with `-ProjectRoot` and
  `-InputPaths`; the script computes input and workspace hashes.
- Update the attempt status (`passed`, `failed`, `rejected`) via `update-attempt-record.ps1`. If an attempt fails, record the `failure_class` and `recovery_action`.

### 4. Execute Verification Envelope
Run automated tests inside the envelope:
```powershell
powershell.exe -NoProfile -Command "& .\src\scripts\invoke-verification-envelope.ps1 -Name 'feature-suite' -Command 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/feature.tests.ps1' -SourcePaths 'docs/feature.md' -TestPaths 'tests/feature.tests.ps1' -TestResultPath 'artifacts/test-results/feature.json' -RequireTestsCollected -RequireStructuredTestResult -AcceptanceCriteria 'docs-content-valid','references-valid'"
```

### 5. Render Report and Arbitration
Render the attempt report with `render-completion-report.ps1` and submit a completion claim to `invoke-completion-gate.ps1`.

---

## Tier 0 vs Tier 1 Routing

- **Tier 0 (Lightweight Read-only)**: Follow `src/AGENTS.md` directly. Suitable for brief searches, code queries, and read-only inspections without loading heavy policies.
- **Tier 1 (Reliable Maker Control)**: For multi-step, file write, migration, or high-risk tasks, explicitly load `src/skills/reliable-maker-control/SKILL.md`. Always state whether Tier 1 policy was read.

## Evaluation Conversations

- Use a fresh Antigravity conversation for each independent Canary, baseline,
  candidate, or adversarial case so earlier Skill names and corrections do not
  contaminate routing behavior.
- Keep planning, execution, attempts, and recovery for one logical task in the
  same conversation.
- Use a separate fresh conversation for an independent Reviewer or Checker.
