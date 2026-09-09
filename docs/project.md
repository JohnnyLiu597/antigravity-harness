# Project — Antigravity Harness v4 convergence

## Purpose

Maintain the reliability and governance layer for Google Antigravity Desktop.
The source repository, explicitly installed .gemini runtime and private operational
state are separate. This is not a different-engine harness or an application patch.

## Current delivery

Six work packages are tracked together in artifacts/plan_v4_convergence.md and
docs/v4-requirements.md: opt-in policy/Binding, opaque execution limits, Tool Operations,
explicit completion/Stop, optional Knowledge Gate and recoverable release operations.

Current engineering and installation evidence is docs/v4-release.md. The ordinary
workflow and limitations are docs/v4-operations.md. Initial installed v3.5.1 matched
71 source files; historical case-02 hash and Pre/Post/deny counts were independently
read and replayed in isolation, not rerun at the original location.

Production closeout is documented in docs/production-readiness.md: specified v4
desktop scenarios observed; both acceptance Attempts stopped; revoked Binding
preserved. Limited supervised use is permitted, but canonical completion remains
unverified due to missing final Claim and stale first-Attempt evidence. This is a
declared limitation, not a silently waived Gate. Feature work is frozen.

## Risks and non-goals

Same-user state/terminal bypass and host TOCTOU remain; strict is unavailable.
No trusted checker/parent-child identity. No complete shell effect parser.
No promise of factually infallible models or unstoppable execution.
Knowledge media semantics are blocked if originals cannot be read natively.
Real Obsidian installation needs separate authorization. No extra model API/local AI.
No automatic history deletion. No commits, pushes or PRs during this implementation.

## Maintenance

Retain failed regression, review and rollback evidence. Rerun the unified release
check after relevant changes. Use explicit transaction/claim/gate references for
recovery; never reconstruct state from the latest modification timestamp.
# 2026-09-10 collaboration upgrade

Codex verification reductions do not apply to Antigravity execution or its
review. The new shared coordination script and strict native wrapper preserve
required checks, fresh hashes, guarded restrictions and completion authority.
See [collaboration](agent-collaboration.md). Existing v4 tests remain mandatory;
new protocol tests add coverage rather than replacing them. Runtime installation
and Desktop observation remain separate evidence layers.
