# Antigravity Native Surfaces Guide

This guide describes the intended Antigravity-native mappings. In the current
source environment these in-app surfaces are `policy-only / unverified` until a
live Antigravity canary proves their names, schemas, availability, and behavior.

---

## 1. Native Human-in-the-Loop: `ask_question`

When the active runtime exposes a verified `ask_question` surface, use it for
structured user approval instead of text stop-words. If the surface is absent
or unverified, stop and ask the user normally; do not pretend that a modal was
shown.

### When to Use `ask_question`
- **Destructive Operations (Tier 3 Permissions)**: Deleting files, modifying database schemas, dropping resources, publishing packages.
- **Ambiguous Requirements / Design Branches**: When multiple valid architectural paths exist and user intent must be locked.
- **Project Identity Resolution**: When repo metadata and user instructions have conflicting signals.

### Best Practices
```json
{
  "questions": [
    {
      "question": "Which database migration strategy should we adopt?",
      "options": [
        "(Recommended) Forward-only additive migrations with zero downtime",
        "Destructive recreate with fresh fixtures for dev environment",
        "Manual SQL patch script"
      ],
      "is_multi_select": false
    }
  ]
}
```
- List recommended options first with `(Recommended)`.
- Never provide an explicit "Other" option; the UI provides a write-in field by default.
- Format options as the user's direct response.

---

## 2. Native Planning Mode

When live evidence confirms Planning Mode, its private runtime locations are:
- Plans reside under: `~/.gemini/antigravity/brain/<conversation-id>/implementation_plan.md`
- Verification summaries reside under: `~/.gemini/antigravity/brain/<conversation-id>/walkthrough.md`

### Harness Rules for Planning
1. **Never write `artifacts/plan_*.md` to the target repository root**: This clutters the user's project and creates state duplication.
2. **Phase Boundary Stop**: When in Planning Mode, write the plan artifact with `RequestFeedback = true`, present the plan, and stop to await user approval before touching source files.
3. **Walkthrough Closure**: On task completion, write a `walkthrough.md` artifact detailing changes made, tests executed, and evidence collected.

---

## 3. Asynchronous Orchestration & Reactive Wakeup

The intended orchestration contract is event-driven rather than an active
polling loop. Reactive wakeup remains unverified until exercised in a canary:

```
┌────────────────────┐     invoke_subagent     ┌─────────────────────┐
│  Coordinator Agent ├────────────────────────►│   Subagent Worker   │
└─────────┬──────────┘                         └──────────┬──────────┘
          │                                               │
          │ stop calling tools                            │ performs work
          ▼                                               ▼
┌────────────────────┐   automatic reactive    ┌─────────────────────┐
│  Agent Suspended   │◄────── message ─────────┤ Subagent Completes  │
└────────────────────┘                         └─────────────────────┘
```

### Key Principles
- **No Polling Loops**: Never run `while ($true) { sleep 5 }` or loop on `manage_task(Action='status')`. Stop calling tools and let the harness suspend your turn.
- **Reactive Wakeup**: When a subagent or background task finishes, Antigravity automatically awakens the parent agent with high-priority notifications.
- **`schedule` Tool**: Use for one-shot timers (`TimerCondition='any'`) or recurring crons rather than blocking shell sleeps.

---

## 4. Multi-Agent Delegation: `invoke_subagent` & `define_subagent`

When a live capability probe confirms the relevant tools, Antigravity may use
dynamic or pre-configured subagents:

### Minimal Context Packages (No Context Bleed)
When delegating work via `invoke_subagent`, never paste the entire parent conversation history. Provide strictly:
1. **Specific Sub-Goal**: 1 sentence, unambiguous.
2. **Essential File Paths**: Absolute paths to the exact files the worker needs.
3. **Tool Allowlist**: Restrict worker to read-only tools unless file writing is required.
4. **Output Contract**: Precise schema and destination for the worker's result.

### Communication
- Use `send_message` with the recipient's `conversationId` for inter-agent communication.
- Use `manage_subagents(Action='kill_all')` to cleanly reap background workers once their results are synthesized.
