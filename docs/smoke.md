# Smoke Verification

Smoke tests are fast critical-path checks, not a substitute for the complete
behavioral regression suite.

Minimum source smoke:

1. Parse all PowerShell scripts.
2. Parse all JSON schemas and manifests.
3. Verify manifest integrity and component TTL.
4. Run truth, control, verification, and governance tests.
5. Run bidirectional sync-boundary tests.
6. Preview source-to-runtime synchronization.

A live runtime smoke additionally proves only the Antigravity surfaces actually
exercised by the canary. Missing login, quota, desktop state, or CLI access is a
blocked verification, never an implicit pass.
