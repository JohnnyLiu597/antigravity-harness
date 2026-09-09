> Redacted historical observation: identifiers removed; originals remain private. Current behavior is defined by the v4 documentation.

# Antigravity Desktop Hook Probe — Live Evidence 2026-09-06

## Conditions

- Desktop product: Antigravity 2.12.2 on Windows.
- Plugin: `antigravity-reliable-control`.
- Hook: `PreToolUse`, matcher `list_dir`.
- Handler mode: `observe-only-fail-open`.
- Conversation: fresh desktop conversation after application restart.
- User request: one read-only root directory listing, with no terminal or write.

## Host-Observed Event

```json
{
  "schema": "antigravity-desktop-hook-probe-event-v1",
  "event": "PreToolUse",
  "tool_name": "list_dir",
  "step_idx": 2,
  "conversation_id_sha256": "e5646deceafc60fe847bdcd5ad7eda2c6337e044b37b06336adac6d3ed32e58e",
  "workspace_count": 1,
  "enforcement": "observe-only-fail-open"
}
```

Event file SHA-256:

```text
ce768e98785ec20cfef3710a395a413818a1c160bea914c37e15e1eb7953d2cc
```

The event was created at `2026-09-05T17:49:17.8216619Z`, corresponding to
2026-09-06 01:49:17 in Asia/Shanghai.

## Privacy Check

- No raw Windows absolute path was present.
- No raw conversation UUID was present.
- No raw tool arguments, prompt, transcript, or tool output were persisted.
- The runtime state directory contained `.gemini-private`.

## Decision

The Antigravity Desktop build automatically loaded the plugin and invoked the
documented PreToolUse handler for a real native `list_dir` call. The probe is
therefore `verified` and `available` as a host-observed, script-handled surface.

This does not prove mutation denial, automatic Attempt creation, PostToolUse
correlation, role binding, or Stop enforcement. Those remain unverified and are
not enabled by this Probe.
