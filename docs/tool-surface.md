# Tool And Native Surface Truth

Every capability is classified separately by implementation, availability, and
enforcement. Supported values are defined in `src/harness.capabilities.json`.

- `native-enforced`: a live canary proves the Antigravity runtime enforces it.
- `script-enforced`: a deterministic local script enforces the contract.
- `human-enforced`: user approval is the authority.
- `policy-only`: the model is instructed, but the runtime does not prove it.
- `unverified`: available evidence is insufficient.

Static PowerShell inspection can verify files, hashes, schemas, commands, and
source/runtime drift. It cannot prove in-app `ask_question`, Planning Mode,
`manage_task`, `schedule`, reactive wakeup, subagent tools, or model routing.
Those surfaces remain unverified until a live Antigravity canary records safe
evidence.

Model names and thinking tiers must be discovered from the active runtime.
Reusable rules must not hard-code an unavailable model or silently change
verification requirements when a cheaper or fallback model is selected.
