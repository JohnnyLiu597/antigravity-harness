# Session Binding Fail-Closed Implementation Plan

**Goal:** Replace ineffective Canary `force_ask` decisions with hard deny while preserving active-binding allow and unrelated-path compatibility.

- [x] Change missing and terminal-binding tests from `force_ask` to `deny` and observe RED.
- [x] Change Canary binding failures to `deny` and retain Sentinel precedence.
- [x] Confirm active canonical running Attempt remains `allow`.
- [x] Confirm unrelated project writes remain observe-only `allow`.
- [x] Run full verification and install runtime/plugin.
- [x] Close failed case-01 Attempt and initialize fresh case-02.
- [x] Do not commit or push.
