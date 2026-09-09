# Antigravity Harness — Baseline Rules v2.0
> Tier 0 baseline for Google Antigravity and Gemini CLI.
> `GEMINI.md` is a policy-only Tier 1 profile, not proof of native enforcement.

## 1. Runtime and Context
- Use the Antigravity / Gemini CLI runtime only.
- Load: `AGENTS.md` → `mission.md` → `CONTEXT.md` → `.agent/rules.md` → `MEMORY.md` → `README.md`.
- Treat native tools, model routes, lifecycle behavior, and skill loading as `unverified` until current runtime evidence proves availability.

## 2. Windows-First Safety
- Prefer PowerShell and probe commands with `Get-Command`.
- Never run disk formatting, root-recursive deletion, registry mutation, or system-process termination.
- Soft-delete project files to `.gemini-trash/<yyyyMMdd-HHmmss>/`; never permanently delete by default.
- Do not mutate `$env:USERPROFILE\.gemini` directly; use reviewed sync or state scripts.

## 3. Bounded Execution
- Lock project identity, objective, non-goals, allowed paths, change budget, checks, and approval triggers before substantial writes.
- Scope expansion, dependency changes, migrations, destructive actions, deployment, and publication require explicit user approval through `ask_question` when that surface is available.
- Identical tool and input with the same deterministic error twice means stop, inspect state, and change one assumption; three failed attempts require `blocked` or user input.
- A tool call being attempted or executed is not evidence that the objective passed.

## 4. Completion Truth
- Use the states defined in `GEMINI.md`: planned, attempted, executed, partial, passed, checking, unverified, blocked, verified, approved.
- Record material operations with script-derived input/workspace hashes and side effects; render final reports from the ledger and preserve `passed_after_retry`.
- Manually assembled contract/ledger/envelope/decision JSON is not canonical evidence; require producer hashes and governed-execution audit.
- Makers, test authors, runners, and reviewers may provide evidence; the source-only gate remains `checking`, and only an externally attested gate may assign `verified`.
- Never report completion without fresh evidence bound to the current source state.

## 5. Privacy and Observability
- `.gemini-private` is a marker file only, never a state directory.
- Harness-private state belongs under `$env:USERPROFILE\.gemini\harness-state\`, which contains its own `.gemini-private` marker.
- Persist safe metadata and hashes only; never raw prompts, raw tool input, raw tool output, transcripts, secrets, or hidden reasoning.

## 6. Project Identity Gate
- Evidence ranking: current user statement > existing anchors/manifests > code inference.
- If identity or authority remains unclear, use `ask_question` when available; otherwise ask one concise question.
- Before identity is locked, do not scaffold, write, or fan out implementation workers.

## 7. Tier 1 Policy Selection
- `GEMINI.md` is a small global router. For mission-backed, long-running, multi-step, write, delegated, or high-risk work, read `skills/reliable-maker-control/SKILL.md` completely.
- Conditional loading is policy-only and must be reported inactive/unverified when the skill was not actually read.
- Evaluate independent routing cases in fresh conversations; prior Skill names make later cases context-contaminated.
- IAS is an advisory self-observation only; objective scope, progress, fingerprints, independent checks, and the completion gate control decisions.

## 8. Authority
- Maker and checker roles must remain separate for major, security-sensitive, migration, release, and long-running work.
- The user retains final authority for scope expansion, destructive actions, migration, merge, deployment, publication, and release.
- Runtime preferences and project-specific narrowing belong in `GEMINI.md` and `.agent/rules.md`; neither may weaken user authority or privacy boundaries.

## 9. Explicit Codex Collaboration
- Preserve neighboring Codex governance files. Use the cross-engine-handoff skill for actual task exchange; it does not install another runtime.
- Codex-only verification reductions do not apply to Antigravity-origin or mixed work, including when Codex reviews it.
- Keep all required checks, fresh hashes, Contract/Attempt/Binding, guarded restrictions and native completion authority. Shared leases/evidence grant no native permissions or acceptance.
- Use scripts/invoke-antigravity-handoff.ps1 for strict handoff; Release may stop without passing. Never use the common helper to bypass the fresh native gate.
