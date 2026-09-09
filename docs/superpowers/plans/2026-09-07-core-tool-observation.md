# Core Tool Observation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use TDD and execute this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Extend the verified Antigravity Desktop Pre/Post Hook from `list_dir|run_command` to the core read, write, edit, and subagent tools, and provide a deterministic session coverage audit.

**Architecture:** Keep all newly covered tools observe-only. Reuse host conversation hash plus step index for Pre/Post correlation, add bounded target-path hashes and subagent counts, and summarize coverage without reading transcripts or storing raw arguments. Exact Sentinel denial remains the only active deny rule.

---

### Task 1: RED Coverage Contract

- [x] Add failing tests for the expanded matcher, core tool Pre/Post pairs, target hashes, privacy, and session audit output.
- [x] Add failing governance tests for source-fidelity versus external-truth separation and Final Claim Set propagation.
- [x] Confirm failures are caused by missing v3.3 behavior.

### Task 2: Core Hook Observation

- [x] Extend PreToolUse/PostToolUse matchers to the bounded core tool set.
- [x] Record only target path hashes, target count, and requested subagent count in addition to existing safe metadata.
- [x] Keep all newly covered tools allow/observe-only.

### Task 3: Session Audit

- [x] Add `audit-desktop-hook-session.ps1` to report Pre/Post counts, matched success/failure, denied calls, missing Post, orphan Post, and by-tool coverage.
- [x] Do not read transcript files or output raw conversation IDs, paths, arguments, prompts, or errors.

### Task 4: Truth Policy And Release

- [x] Add source-fidelity/external-truth and Final Claim Set policies to Tier 1.
- [x] Update capabilities, components, package verification, and docs.
- [x] Run focused RED→GREEN, 11/11 behavioral evals, package verification, installed gate, and hash comparison.
- [x] Install runtime and desktop plugin transactionally.
- [x] Do not commit or push.
