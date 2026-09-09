# Desktop Hook Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a reversible, fail-open Antigravity Desktop `PreToolUse` probe that observes only `list_dir` and proves the host hook contract without gating mutations.

**Architecture:** Keep plugin source under `src/desktop-hooks/antigravity-reliable-control` and deploy it separately to `~/.gemini/config/plugins/antigravity-reliable-control`. The hook receives JSON on stdin, writes only hashed metadata under the private harness-state root, and always returns `decision=allow`, including malformed-input and logging-failure paths.

**Tech Stack:** PowerShell 7/Windows PowerShell, CMD wrapper, Antigravity JSON Hooks, JSON manifests.

---

### Task 1: Deterministic Probe Contract

**Files:**
- Create: `src/harness-evals/test-desktop-hook-probe.ps1`
- Modify: `src/harness-evals/run-harness-evals.ps1`

- [x] Write a failing test requiring plugin metadata, `list_dir`-only matching, fail-open output, private hashed logs, malformed-input recovery, and an installer dry run.
- [x] Run the test and confirm it fails because the plugin and installer do not exist.

### Task 2: Fail-Open Desktop Plugin

**Files:**
- Create: `src/desktop-hooks/antigravity-reliable-control/plugin.json`
- Create: `src/desktop-hooks/antigravity-reliable-control/hooks.json`
- Create: `src/desktop-hooks/antigravity-reliable-control/hooks/pre-tool-use.cmd`
- Create: `src/desktop-hooks/antigravity-reliable-control/hooks/pre-tool-use.ps1`

- [x] Implement the smallest handler that parses official hook input, logs hashes and bounded metadata, and always returns `allow`.
- [x] Run the focused test and confirm it passes.

### Task 3: Transactional Desktop Installation

**Files:**
- Create: `deploy/install-desktop-hook-plugin.ps1`
- Modify: `deploy/verify-package.ps1`
- Modify: `src/harness.components.json`
- Modify: `src/harness.capabilities.json`

- [x] Add dry-run, backup, copy, hash verification, enable/disable, and rollback-manifest support without touching other plugins or `config.json`.
- [x] Run package verification and the full behavioral eval suite.
- [x] Install the probe plugin into the desktop customization directory and compare every installed hash.

### Task 4: Documentation And Live Handoff

**Files:**
- Modify: `CONTEXT.md`
- Modify: `MEMORY.md`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/commands.md`
- Modify: `docs/v2-upgrade.md`
- Create: `docs/v3-hook-probe.md`

- [x] Record the distinction between statically installed, live-observed, and native-enforced.
- [x] Run the installed verification gate and `git diff --check`.
- [x] Do not commit or push.
