# Mission

Maintain the Google Antigravity Desktop reliability and governance harness as a versioned engineering project.

The harness raises the reliability floor of Google Antigravity Desktop
agents during long-running engineering work by providing:

1. a lightweight baseline with truthful `policy-only` versus enforced claims;
2. task contracts, scope budgets, resumable job state, and idempotent effects;
3. causal verification tied to current workspace fingerprints;
4. maker-checker separation and user-owned high-risk approval;
5. transactional PowerShell source/runtime synchronization without private data.

## Non-Negotiables

- **Antigravity Desktop Native**: Desktop is the v4 delivery target. Existing CLI/PowerShell helpers remain utilities, not evidence that Desktop, IDE, CLI and SDK interfaces are interchangeable. Native surfaces remain unverified until version-specific live evidence proves them.
- **Windows-First & PowerShell-First**: Native PowerShell scripts with strict syntax verification and reparse-point guards.
- **Three Rigid Boundaries**:
  1. *Versioned Source Package* (`src/`): Clean, inspectable, public-ready.
  2. *Local Runtime Layer* (`$env:USERPROFILE\.gemini`): Installed functional surface.
  3. *Private State (Forbidden)*: Credentials, session transcripts, conversation SQLite/PB state, and local cache artifacts.
- **Strict Line Budget**: `src/AGENTS.md` must remain under 80 lines to maintain a low global token tax.
- **Verify Before Claiming Done**: `verify-package.ps1` and boundary integration tests must pass before declaring any harness modification complete.
- **Completion Truth**: A maker may provide evidence, but only an externally attested completion gate may assign `verified`; the source-only gate remains `checking`, and deployment/publication approval belongs to the user.

## Success Criteria

- `src/` contains the maintainable harness payload (rules, skills, agents, scripts, templates, registries).
- `deploy/verify-package.ps1` passes with zero failures or leaks.
- `deploy/test-sync-boundaries.ps1` passes all bidirectional boundary test cases.
- `deploy/sync-to-runtime.ps1 -DryRun` accurately forecasts deployment actions.
- Published source package contains zero personal usernames, local filepaths, or provider tokens.
- Manifest integrity contains no phantom scripts, stale component TTL, or unsupported native-enforcement claims.
- Behavioral regressions prove scope, recovery, exit-code, stale-verification, and maker-checker contracts.
