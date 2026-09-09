---
name: memory-extract
description: Consent-aware extraction of stable, non-sensitive decisions and recovery pointers.
---

# Memory Extraction

Extract only durable information that materially improves future work. This skill is a
policy-only procedure; a SHUTDOWN policy mention does not prove automatic execution.

## Eligible Memory

A memory must be:

- non-obvious and stable;
- actionable for the same user or project;
- supported by an accepted decision or verified evidence;
- non-sensitive and free of credentials, session content, or private runtime data;
- within the user's requested project scope.

Examples include explicit project decisions, stable development conventions, verified
command paths, and public reference links. Do not infer a preference from a single
uncorrected interaction.

## Storage

Private memory records belong under
`$env:USERPROFILE\.gemini\harness-state\memory\`. The state root contains a
`.gemini-private` marker file; the marker is not a directory. Store safe metadata and
hashes when a direct value is unnecessary.

A project `MEMORY.md` may contain a concise index only when the project permits edits
and the memory is appropriate for shared, versioned context. Keep it under 200 lines
and link to project-safe facts rather than runtime-private records.

## Privacy Contract

Never persist a raw prompt, raw tool input, raw tool output, transcript, hidden
reasoning, secret, token, cookie, authentication data, personal identifier, or private
file contents. Do not copy a conversation merely to make it searchable.

## Trigger and Truth

Run only when the user requests memory, the project workflow explicitly calls for a
handoff, or an approved lifecycle policy selects it. Record whether extraction was
`planned`, `executed`, or `passed`; never claim it ran solely because SHUTDOWN was
reached. Memory content cannot assign `verified` to the source task.
