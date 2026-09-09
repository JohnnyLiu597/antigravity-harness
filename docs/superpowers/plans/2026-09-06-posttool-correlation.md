# PostToolUse Correlation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically correlate allowed Antigravity Desktop `PreToolUse` events with `PostToolUse` success or failure using host-issued conversation and step identity.

**Architecture:** PreToolUse writes a deterministic correlation record keyed by hashed conversation ID and step index. PostToolUse receives the same host fields, resolves the pre record, and writes a separate immutable completion record containing only status and error hash. Denied sentinel calls remain terminal at PreToolUse and do not require a Post event.

**Tech Stack:** Antigravity Desktop JSON Hooks, Windows PowerShell 5.1, CMD wrappers, JSON evidence.

---

### Task 1: Correlation Regression

- [x] Extend `test-desktop-hook-probe.ps1` with successful, failed, orphan, and malformed PostToolUse cases.
- [x] Run the focused test and confirm it fails because PostToolUse assets are missing.

### Task 2: Pre/Post Handlers

- [x] Add deterministic pre correlation records without raw paths or commands.
- [x] Add `post-tool-use.ps1` and `.cmd` wrapper that always returns `{}`.
- [x] Verify successful and failed calls pair by conversation hash and step index.
- [x] Verify raw errors and commands are not persisted.

### Task 3: Package And Installation

- [x] Add PostToolUse to `hooks.json` for `list_dir|run_command`.
- [x] Update package, component, capability, and documentation manifests.
- [x] Run 11/11 behavioral regressions, package verification, and diff checks.
- [x] Transactionally install the normal runtime and desktop plugin.
- [x] Do not commit or push.
