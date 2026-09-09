# Agent Rules

> Project-specific constraints for the Antigravity harness.
> Install at `.agent/rules.md`; these rules may narrow but never weaken global safety.

## Project Identity

- **Project name**: <!-- project name -->
- **Objective**: <!-- one bounded objective -->
- **Non-goals**: <!-- explicit exclusions -->
- **Runtime preference**: Antigravity / Gemini CLI on Windows and PowerShell
- **Runtime root**: `$env:USERPROFILE\.gemini`
- **Private state root**: `$env:USERPROFILE\.gemini\harness-state\`
- **Private marker**: `.gemini-private` is a marker file inside the state root, never a directory
- **Project soft-delete**: `.gemini-trash/<yyyyMMdd-HHmmss>/`

## Enforcement Truth

- Instruction files and role templates are `policy-only` unless a current native probe
  or deterministic script proves enforcement.
- Treat native tools, lifecycle hooks, model routes, skill loading, and Planning Mode as
  `unverified` until current runtime evidence exists.
- A documented or registered capability is not necessarily implemented, available, or verified.

## Task Contract

Before substantial writes, lock:

- allowed and denied paths;
- maximum files and line-change budget;
- whether dependency, lockfile, architecture, schema, or deployment changes are allowed;
- required checks and their evidence requirements;
- approval triggers, checker identity, stop condition, and rollback expectations.

Scope expansion, dependency changes, migration, destructive operations, external writes,
merge, deployment, publication, and release require explicit user approval. Approval is
authorization for the named action, not evidence that it succeeded.

## Completion Truth

Use: `planned`, `attempted`, `executed`, `partial`, `passed`, `checking`, `unverified`,
`blocked`, `verified`, and `approved`.

- Tool return means `executed` at most.
- One passing check means `passed` for its recorded inputs only.
- Missing, stale, mismatched, or ambiguous evidence means `unverified`.
- The source-only completion gate may validate evidence but remains `checking`;
  only trusted external checker attestation may promote it to `verified`.
- IAS and model judgments are advisory and cannot approve scope or completion.

## Role Permissions

### Read-Only Review Roles

Architect, Reviewer, Explorer, and Harness Auditor may inspect allowlisted source, actual
diffs, and sanitized evidence. They must not edit files, execute mutating commands, or
authorize high-risk work. The Reviewer may reject a claim but cannot assign `verified`.

### Maker

- May inspect and edit only task-contract-owned product paths.
- May run scoped, non-destructive checks.
- Must not self-verify, enlarge scope, alter acceptance criteria, or authorize merge,
  deployment, publication, or release.

### Test Author

- May edit assigned test files only and run the minimal reproducer.
- Must not edit product code or weaken assertions to accommodate implementation.
- Must not assign `verified`.

### Test Runner

- May read source, tests, actual diff, and sanitized evidence.
- May use `run_command` only for allowlisted, non-destructive verification with a finite timeout.
- Must not edit or modify product, source, or test code, install dependencies, or change lockfiles.
- Must preserve the real child-process exit code and current source fingerprint.
- Must not assign `verified`.

Tool names and role enforcement remain policy-only until the runtime proves them.

## Safe Tool Use

- Probe command availability before use and prefer PowerShell on Windows.
- Never run root-recursive deletion, disk formatting, registry mutation, or system-process termination.
- Never mutate `$env:USERPROFILE\.gemini` directly; use reviewed sync or state scripts.
- Before retrying a timeout or external write, observe whether the previous attempt changed state.
- Stop identical deterministic failures on the second observation; after three failed attempts,
  enter `blocked` or request user input.

## Private State and Observability

Harness-owned jobs, failures, trajectories, evals, verification, memory, and orchestration
records belong under the private state root. The `.gemini-private` marker protects that
root from sync; do not store data in the marker.

Records contain safe metadata and hashes only, such as timestamp, event type,
repository-relative target, branch, commit, changed-path count, exit code, timeout flag,
retry count, duration, state transition, evidence reference, and bounded fingerprints.

Never persist a raw prompt, raw tool input, raw tool output, command payload, patch body,
assistant message, transcript, secret, credential, cookie, auth state, private environment
value, or hidden reasoning.

## Forbidden Content and Reads

- Do not read, copy, reveal, or version credentials, tokens, private runtime state,
  SQLite/PB session data, browser state, plugin cache, or authentication files.
- Do not include user-specific absolute paths in committed source; use environment variables.
- Do not create a second execution runtime.
- Do not hide unapproved artifacts by modifying `.gitignore`.
- Use `.gemini-trash` for recoverable project cleanup; permanent deletion needs explicit approval.

## Verification Requirements

Before requesting completion:

1. Run the smallest required deterministic checks against the current source state.
2. Preserve real exit codes, timeout status, test collection counts, and fingerprints.
3. Classify failures as task-caused, pre-existing, environment, permission, timeout,
   tool-defect, assumption-error, or insufficient-evidence.
4. Invalidate evidence after changes to source, tests, graders, configuration, or protected inputs.
5. Require an independent Reviewer for major, security-sensitive, migration, release, or
   long-running work.
6. Submit evidence to the completion gate; do not turn a summary into proof.

The user retains final authority for destructive work, migrations, merge, deployment,
publication, release, and every material expansion of scope.

---

*Generated from `src/templates/agent-rules.template.md` — Antigravity Harness*
