# Contributing

Keep changes scoped, Windows-first, and verifiable. Include the observed failure,
affected Desktop/version context, expected behavior, smallest reproduction and
the exact checks performed. Do not generalize one local observation to every model
or product version, and do not turn a policy-only mechanism into an enforcement claim.

- Preserve Antigravity contracts, required checks, fresh evidence and guarded
  restrictions. Codex verification reductions are not a license to weaken them.
- Add synthetic regression fixtures; never commit raw user sessions or credentials.
- Run the nearest regression first. For shared contracts, gates, sync or publication
  boundaries, run deploy/test-v4-release.ps1. Keep failures and rollback evidence.
- For documentation-only changes with unchanged tested code, verify links and
  package boundaries and identify the existing code evidence instead of rerunning
  unrelated suites. This does not waive a business task's native acceptance.
- Do not claim line coverage, native activation, OS isolation or trusted checker
  identity from suite counts. Report unperformed checks explicitly.
- Preserve license notices and explain source/runtime compatibility and rollback.

This snapshot keeps original local history private. Do not import old logs or
history merely to make provenance appear more complete.
