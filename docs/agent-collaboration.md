# Asymmetric collaboration with Codex

This upgrade preserves the existing v4 strong execution constraints and evidence
system. This wording does not mean the unavailable strict isolation mode works.
Only Codex-authored ordinary work receives verification-cost reductions. A Codex
review of Antigravity output still follows the original full required checks.
All Contract/Attempt/Binding, current source/test/producer hashes, native guarded
denials, Completion Gate and independent authority requirements remain unchanged.

Use the cross-engine-handoff skill and `src/scripts/invoke-antigravity-handoff.ps1`.
Init the shared task with the existing native logical task ID, objective, literal
allowed paths and required check IDs. Acquire a checkout-wide writer using the
observed revision and local session reference. For Handoff, supply exact
`-NativeTaskRoot` and `-DecisionPath`; the native governed audit reruns its original
Completion Gate. Without a valid current chain, Handoff is refused. Release can
stop work without claiming acceptance. Never use a generic shared helper as an
alternative to this strict adapter.

Shared task state lives in `artifacts/agent-collaboration/`. It retains required
checks and raises policy monotonically to `antigravity-strict`, including on the
return to Codex. RecordEvidence only saves exact file references and SHA-256;
shared acceptance remains unverified. State and lease tokens are coordination,
not authority, authentication, OS isolation, or permission to run a denied tool.
Stop old commands before handing off. Use separate worktrees for concurrent edits.

The common script and fixtures are reviewed copies from codex-harness. Their
checksums must match at release. Antigravity owns the strict wrapper and native
governance. There is no shared scheduler and no automatic verification cache.

## Skills and native surface status

There are no legacy workflows to migrate in the observed baseline. The existing
skills get a canonical discovery mirror in `.gemini/config/skills`; the legacy
`.gemini/skills` entry remains compatible. Both derive from one source. Import
must reject divergent same-name copies; no whole config directory is imported.

Official documentation now describes Stop, but this release does not register or
activate a new Desktop Stop hook. The existing bounded-stop helper is not proof
of native activation or checker identity. Current Desktop activation requires a
separate version-specific observed canary; prior unverified history is preserved.

Sources checked 2026-09-10:

- [Google Hooks](https://www.antigravity.google/docs/hooks/)
- [Skills migration](https://www.antigravity.google/docs/migration/workflows-to-skills/)
- [Project worktrees](https://www.antigravity.google/docs/projects/)
