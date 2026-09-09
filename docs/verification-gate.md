# Verification And Completion Gates

Verification must prove the claim against the current workspace, not merely
show that a command was invoked.

An envelope records hashes for the command, source, tests, grader, safe output,
environment, protected paths, and evidence. It also records the real child
process exit, timeout state, test collection counts when provided, Git commit,
dirty state, and before/after workspace fingerprints.

The gate fails when:

- a required source, test, grader, evidence, or protected path is missing;
- the child exit is nonzero even if stdout resembles success JSON;
- no tests were collected when a positive collection count is required;
- a claimed test command is not syntactically bound to a declared test path;
- an acceptance criterion is absent or not passed in the structured
  `antigravity-test-result-v1` artifact;
- a timeout leaves the command incomplete;
- input or protected-path hashes change unexpectedly;
- the envelope belongs to an older commit or workspace fingerprint;
- the requester is a maker attempting to issue `verified`;
- the completion requester is not the named independent checker, or an
  acceptance evidence hash does not match the verified envelope;
- an Attempt Ledger evidence artifact is missing or its current hash differs;
- contract, ledger, report, envelope, or decision producer hashes do not match
  the canonical scripts;
- high-risk work lacks user approval or independent checker evidence.

The source-only gate emits `checking` after deterministic predicates pass,
because project-local JSON cannot prove checker identity. `verified` remains
reserved for a future live/native or human-attested authority whose trust
boundary is independently proven. Failed predicates emit `unverified` with
missing evidence.
