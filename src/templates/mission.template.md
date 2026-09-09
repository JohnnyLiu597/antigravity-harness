# Mission: {{PROJECT_NAME}}

> This file defines the project's mission, constraints, and success criteria.
> It is a context anchor loaded at session start by the Antigravity harness.

## Primary Goal

{{PRIMARY_GOAL}}

## Constraints

{{CONSTRAINTS}}

<!--
Example constraints:
- No new runtime dependencies without explicit approval
- All file operations must use soft-delete via .gemini-trash
- Context anchors must remain under 8KB each
- Windows PowerShell compatibility required for all scripts
- No credentials or secrets in committed source
-->

## Success Criteria

{{SUCCESS_CRITERIA}}

<!--
Example success criteria:
- [ ] All verification scripts pass on a clean Windows machine
- [ ] No critical findings from harness-auditor
- [ ] Context anchors are consistent and non-contradictory
- [ ] All components are in active or experimental state with valid TTLs
-->

## Scope Boundaries

### In Scope

- <!-- List what this project explicitly covers -->

### Out of Scope

- <!-- List what this project explicitly does NOT cover -->

## Key Decisions

| Date | Decision | Rationale | Decided By |
|------|----------|-----------|------------|
| <!-- YYYY-MM-DD --> | <!-- What was decided --> | <!-- Why --> | <!-- Who --> |

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| <!-- Risk description --> | Low/Medium/High | Low/Medium/High | <!-- How to mitigate --> |

---

*Generated from `src/templates/mission.template.md` — Antigravity Harness*
