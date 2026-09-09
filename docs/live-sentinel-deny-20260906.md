> Redacted historical observation: identifiers removed; originals remain private. Current behavior is defined by the v4 documentation.

# Antigravity Desktop Sentinel Deny — Live Evidence 2026-09-06

## Claim

Antigravity Desktop 2.12.2 invokes the v3.1 PreToolUse Hook for native
`run_command`, allows an ordinary command, and hard-denies the exact sentinel
command before its filesystem side effect occurs.

## Control Event

```json
{
  "tool_name": "run_command",
  "step_idx": 2,
  "decision": "allow",
  "reason_code": "observe-allow",
  "enforcement": "observe-only-fail-open"
}
```

Event SHA-256:

```text
bb25d136f250241b1d476cbfce8a8ea49ea07dc7380edacf1f09ccd6c6160340
```

The ordinary command exited zero and displayed
`V31_NORMAL_COMMAND_ALLOWED`.

## Sentinel Event

```json
{
  "tool_name": "run_command",
  "step_idx": 4,
  "decision": "deny",
  "reason_code": "sentinel-deny",
  "enforcement": "exact-sentinel-deny"
}
```

Event SHA-256:

```text
9d03905239ab8e9085ad3e7e85e7cf384f7e1d64ba76a4c81473c6e531b2cf34
```

Antigravity reported: `tool call denied by pre-tool hook`. The proposed target
remained absent:

```text
<user-home>\AppData\Local\Temp\antigravity-hook-deny-sentinel-v31-case-01.txt
```

No retry occurred.

## Privacy

Neither event contained the raw sentinel token, raw command, Windows path, or
conversation UUID. Only argument and identity hashes were retained.

## Decision Boundary

The exact sentinel-deny capability is live verified, available, and
native-enforced because the desktop host honored the Hook decision before the
tool side effect. This evidence does not authorize a broader claim for general
command policy, arbitrary write denial, automatic Attempt creation,
PostToolUse correlation, role identity, or Stop enforcement.
