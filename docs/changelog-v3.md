# Historical v3 context snapshots

Preserved from the pre-v4 dirty worktree on 2026-09-09. These snapshots contain
superseded and contradictory statements and are not current capability claims.
The current-state authority is CONTEXT.md and the v4 release evidence.

## Prior CONTEXT.md

# Context

This repository is the dedicated, version-controlled source of truth for the Google Antigravity & Gemini CLI agent harness (`antigravity-harness`).

## Current State

- v3.5.1 Fail-Closed Session Binding payload is installed under `$env:USERPROFILE\.gemini` through transaction `42756aff7fc84ab5b6a90ac00dc6a17a`.
- The latest recoverable runtime backup is `$env:USERPROFILE\.gemini\backup-20260908-231332-ddd3dcd0-antigravity-harness-sync\`.
- Truth registry, bounded execution, causal verification, completion truth,
  maker-checker roles, safe observability, behavioral evals, and new sync
  surfaces are present in source.
- Native Antigravity tools, lifecycle activation, and model routing are still
  `unverified` because this PowerShell environment has no live Antigravity CLI
  or in-app canary evidence.
- Contract baseline scope observation, script-derived attempt hashes and side effects, hashed attempt evidence, structured test-case binding, deterministic completion reporting, the global Tier router, and `reliable-maker-control` are installed.
- Empty-workspace contracts, governed TaskRoot registration and explicit transitions, scope assessment modes, and canonical Completion Claim generation are installed.
- The provenance audit now requires TaskRoot, contract, ledger, report, claim, envelope, structured result, and decision metadata. Producer hashes remain audit metadata rather than trusted identity attestation.
- Failed Attempts now retain workspace-after and side-effect evidence even from an empty baseline; incomplete terminal observations fail the Completion Gate and provenance audit.
- Normalized task-intent registration prevents an active governed task from being silently replaced by changing its timestamped LogicalTaskId; RegistryRoot is private-marked.
- The Antigravity Desktop plugin is installed at `$env:USERPROFILE\.gemini\config\plugins\antigravity-reliable-control`; its six files match source and both Windows wrappers pass expanded core-tool simulations.
- All 65 normal runtime targets match source fingerprint `0f2ba07752ca34072eb299416dbcfbb1c49bca3fe9913856e8d43903c5bf4cd3`; rollback was not needed.
- Desktop PreToolUse loading is live-verified for native `list_dir`: a restarted Antigravity 2.12.2 conversation created a privacy-bounded host event at step 2. Mutation gating, PostToolUse correlation, role binding, and Stop enforcement remain disabled/unverified.
- v3.1 exact-sentinel `run_command` denial is live-verified: the desktop host allowed the ordinary command, denied the sentinel at PreToolUse step 4, and the target file remained absent. General command/write gating remains disabled.
- v3.2 Pre/Post correlation is installed and simulated through the installed wrappers for matched failure without raw error leakage; live desktop pairing remains unverified pending restart.
- v3.3 core-tool observation and transcript-free session audit are installed and simulated for `view_file` with matched Pre/Post, target hashing, and no raw path leakage. Expanded desktop coverage remains live-unverified pending a fresh file/subagent Canary.
- The first v3.3 live Canary observed list/view/write/replace/run/manage tools, one missing Post after write parameter rejection, and an independently hooked child `view_file`; parent `invoke_subagent` was not observed.
- v3.4 run-command result classification is live-verified: the main conversation had 10/10 matched Pre/Post events and recorded the nonzero command as failed with host-observed code 1.
- Parent `invoke_subagent` and child `view_file` were both observed in separate host conversation ledgers; trusted parent-child identity binding is still unavailable.
- v3.4 live Canary passed host classification and coverage for seven exposed core tools: 10/10 main Pre/Post pairs, one failed command derived from observed code 1, and one matched child `view_file`. `multi_replace_file_content` remains unavailable in the tested runtime; general writes remain observe-only.
- v3.5 session/task/Attempt binding is implemented and statically verified for one exact TEMP Canary root. It is not enabled as a general project write gate and remains live-unverified.
- The v3.5 case-01 TaskRoot recorded a running Attempt before the live test; the host then executed an unbound write despite the Hook's `force_ask`. Its artifacts are retained for failure closure.
- Live v3.5 disproved `force_ask` as an enforcement boundary on this host: the Hook recorded it, no prompt appeared, and the unbound file was created. v3.5.1 hard-deny behavior is implemented and awaiting a fresh case-02 Canary.
- The failed case-01 Attempt is terminal with `host-force-ask-not-enforced`, exit 0, observed `output.txt` side effect, and hashed failure evidence. Fresh case-02 has a canonical Contract and running `binding-deny-attempt-01`; its output is absent.

## Active Direction

- Repeat autonomous routing evaluation in fresh Antigravity conversations; prior same-chat results are context-contaminated.
- Keep native-only capability claims unverified until a live desktop canary.
- Keep trusted checker attestation unverified until a real external authority boundary exists.
- Commit or publish only after explicit user direction.

## Prior README.md

# Antigravity Harness

A versioned, maintainable harness architecture for maintaining a local Google Antigravity & Gemini CLI work surface.

## Project at a Glance

`antigravity-harness` is a specialized reliability and governance harness for
Google Antigravity and Gemini CLI. It keeps Antigravity productive as a Maker
while externalizing scope, state, verification, review, and user approval.

### Three Explicit Boundaries

1. **The Versioned Source Package**: Clean, inspectable, testable source code located in `src/`, safe to commit and publish to GitHub without personal tokens or machine state.
2. **The Local Runtime Layer**: Installed under `$env:USERPROFILE\.gemini` and `$env:USERPROFILE\.gemini\antigravity`.
3. **Private Runtime State (Strictly Excluded)**: Credentials, session transcripts, conversation SQLite databases, proto states, and local cache artifacts.

---

## Reliable Maker Control Plane

- **Truth Registry**: Declared, implemented, available, verified, and approved
  are distinct states. Missing scripts and unsupported capability claims fail.
- **Bounded Execution**: Task contracts, path allowlists, change budgets,
  monotonic job state, workspace fingerprints, and idempotency metadata.
- **Evidence Closure**: Real exits, finite timeouts, test collection checks,
  stale-input detection, protected-path hashes, and deterministic completion.
- **Attempt Truth**: Append-only attempt history and deterministic reports retain
  failures, rejections, recovery actions, and `passed_after_retry`.
- **Maker-Checker Separation**: Maker, Test Author, Test Runner, Reviewer, and
  Human Approver have separate authority.
- **Native Surface Honesty**: `ask_question`, Planning Mode, background tasks,
  subagents, reactive wakeup, and model routing remain `unverified` until a live
  Antigravity canary proves them.
- **Windows-First**: PowerShell source/runtime sync, verification, and recovery.
- **Tier Router**: A small global `GEMINI.md` routes qualifying work to the
  on-demand `reliable-maker-control` skill; conditional loading remains
  unverified until the next restart canary.
- **Desktop Hook Probe**: v3.0 packages an official Antigravity Desktop
  PreToolUse plugin that observes only `list_dir`, fails open, and records
  privacy-bounded host metadata pending a restart Canary.

---

## Repository Layout

```text
antigravity-harness/
  V2_UPGRADE_PLAN.md   # Current Reliable Maker upgrade contract
  UPGRADE_PLAN.md      # Historical v1 design reference
  README.md            # Project overview & quick start
  docs/                # Maintenance, architecture, commands & release guides
  deploy/              # PowerShell sync and package verification scripts
  src/                 # Maintainable runtime payload source (~/.gemini mirror)
  artifacts/           # [GitIgnored] Local test outputs & verification traces
```

---

## Next Steps

See `V2_UPGRADE_PLAN.md` for the current implementation contract. The source
upgrade does not install into the real `$env:USERPROFILE\.gemini` until source,
staging, behavioral, and live-canary evidence are reviewed.

See `docs/v2-upgrade.md` for the project purpose, implemented v2 changes,
verification evidence, runtime installation record, and remaining unverified
native boundaries.

Current local status: v3.5.1 Fail-Closed Session Binding payload installed transactionally into
`$env:USERPROFILE\.gemini`; 65/65 normal runtime targets and 6/6 desktop plugin
targets matched source, and the installed
verification gate passed. Scope, attempt side effects, evidence artifacts, and
acceptance criteria are now derived from observable files and structured test
cases. Empty workspaces are supported, one logical task retains TaskRoot
continuity, scope reports distinguish pre-write declarations from post-write
observation, and Completion Claims have a canonical producer. Tier 1 discovery
is live-observed once. Failed operations now retain filesystem side effects
even from empty baselines, and incomplete terminal Attempt observations fail
closed. Normalized task intent prevents timestamped ID changes from hiding an
equivalent active governed task. Trusted checker identity remains unverified.
The desktop Probe is live-verified for native `list_dir` in a restarted
Antigravity 2.12.2 session. It remains observe-only; write denial, automatic
Attempt closure, role binding, and Stop enforcement are not enabled.
Ordinary `run_command` calls remain allowed; only the exact v3.1 sentinel token
is denied. A restarted desktop Canary proved the host prevented its filesystem
side effect; this evidence does not yet apply to general mutation policy.
v3.2 adds privacy-bounded PostToolUse success/failure correlation using the
host conversation hash and step index. Installed wrappers correlate correctly;
live desktop pairing awaits restart.
v3.3 expands observe-only coverage to core read, write, edit, command, and
subagent tools and adds a transcript-free session coverage audit. Target
projects retain responsibility for domain-specific semantic gates.
v3.4 no longer treats an empty PostToolUse error as proof that `run_command`
succeeded; it derives the observed tool code from the hashed host step output.
Live evidence confirms complete pairing for seven exposed core tools and
correct failed-command classification; general write denial and trusted
parent-child identity remain future stages.
v3.5 adds a single-path `force_ask` Canary that requires a host conversation to
be externally bound to a canonical Contract and running Attempt before writing.
The live host did not enforce `force_ask`; v3.5.1 replaces invalid Canary
binding decisions with hard deny while unrelated paths remain observe-only.

## Prior MEMORY.md

# Memory

- **Runtime Target**: `$env:USERPROFILE\.gemini` (with Antigravity specific state in `$env:USERPROFILE\.gemini\antigravity`).
- **Private Marker**: `.gemini-private` is a marker file that protects its containing directory. Private harness state lives under `$env:USERPROFILE\.gemini\harness-state\` with this marker.
- **Trash Directory**: Non-destructive deletions are routed to `.gemini-trash/<yyyyMMdd-HHmmss>/`.
- **Baseline Rule Budget**: `src/AGENTS.md` must never exceed 80 lines; keep it strictly around 40-50 lines to prevent global token tax bloat.
- **Completion Truth**: Makers may report progress and request checking; the source-only gate remains `checking` until trusted external checker attestation exists, and only the user may issue high-risk approval.
- **Surface Alignment**: `ask_question`, Planning Mode, background task orchestration, subagents, reactive wakeup, and model routing are policy-only/unverified until live evidence exists.
- **Verification Freshness**: A source, test, grader, evidence, environment, or protected-path change invalidates prior verification.
- **Attempt Truth**: Final reports are rendered from the private Attempt Ledger and must retain failed/rejected attempts and `passed_after_retry`.
- **Tier Reality**: v2.0 loaded Tier 0 and the full Tier 1 globally. v2.1 replaces global `GEMINI.md` with a small router and moves full policy to `reliable-maker-control`; conditional loading needs a restart canary.
- **Evaluation Isolation**: Use a fresh Antigravity conversation for each independent Canary/A-B case and a separate fresh conversation for Reviewer/Checker work; keep one logical task's retries in the same conversation.
- **Observed Evidence**: v2.2 derives Scope deltas, Attempt input/workspace hashes, side effects, evidence hashes, and acceptance case coverage from files instead of model self-report.
- **Execution Provenance**: v2.3 requires canonical producer script hashes plus contract, ledger, report, structured test result, verification envelope, and completion decision before claiming the governed chain ran.
- **TaskRoot Continuity**: v2.4 registers one active TaskRoot per logical task; replacement roots require an explicit prior-root link and transition reason.
- **Scope Phase Truth**: `pre_write_declared` is caller-declared admission evidence; `post_write_observed` is a filesystem-derived after-write audit, not native interception.
- **Claim Provenance**: v2.4 generates Completion Claims with a canonical script. Producer hashes support version auditing but cannot prove actor identity or external checker authority.
- **Failed Side Effects**: v2.5 records workspace-after evidence for failed Attempts even when the initial workspace is empty; a failure is not evidence that no file changed.
- **Intent Continuity**: v2.6 indexes normalized task intent independently of caller-chosen LogicalTaskId. A timestamp or renamed ID cannot silently replace an equivalent active governed task.
- **Desktop Hook Probe**: v3.0 uses the official Antigravity Desktop plugin surface for a `list_dir`-only, fail-open PreToolUse probe. Static installation is not live hook evidence; a restarted desktop Canary must produce a host event before availability changes from unverified.
- **Live Hook Evidence**: A restarted Antigravity 2.12.2 desktop conversation produced a privacy-bounded PreToolUse event for native `list_dir` at host step 2. Probe availability is verified; mutation gating, PostToolUse correlation, role binding, and Stop enforcement remain unverified.
- **Sentinel Deny**: v3.1 matches `run_command` but denies only the exact case-sensitive `ANTIGRAVITY_HOOK_DENY_SENTINEL_V1` token. Ordinary commands remain allow; live side-effect prevention must be proven after restart before promotion.
- **Live Sentinel Enforcement**: Antigravity Desktop allowed the ordinary control command and denied the exact v3.1 sentinel at PreToolUse step 4; the target file remained absent. Native enforcement is verified only for this exact token.
- **Pre/Post Correlation**: v3.2 hashes host conversation identity plus step index to pair allowed PreToolUse calls with PostToolUse success/failure. Raw errors are never persisted; live desktop pairing remains unverified until restart.
- **Core Tool Observation**: v3.3 expands observe-only Pre/Post coverage to list, view, write, edit, command, invoke_subagent, and manage_subagents tools and adds a transcript-free session coverage audit. General mutation denial remains disabled.
- **Source Claim Truth**: Source fidelity is distinct from external truth. Copied hashes are not independent observations, and final outputs must derive from a post-verification Final Claim Set so rejected claims do not survive elsewhere.
- **Tool Result Truth**: An empty PostToolUse `error` does not prove a nested command succeeded. v3.4 derives the observed command result code from the host step output and stores only its hash and numeric code.
- **Subagent Hook Boundary**: A child conversation produced its own `view_file` Hook pair, but the parent `invoke_subagent` call did not appear in the main Hook ledger. Parent-child identity binding remains unverified.
- **Session Binding Canary**: Session binding requires an external host-conversation binding to a canonical Contract, Ledger, running Attempt, writer role, and allowed target. v3.5.1 denies missing or stale bindings for the exact Canary root; unrelated writes remain observe-only.
- **Force-Ask Reality**: The live v3.5 host recorded `force_ask` but displayed no prompt and executed the write. v3.5.1 denies invalid Canary bindings and treats external binding registration as the approval action.
- **v3.4 Live Result**: A fresh main conversation produced 10 matched Pre/Post pairs with one correctly classified failed command; parent `invoke_subagent` and child `view_file` were both observed. The payload still does not provide a trusted parent-child identity binding.
