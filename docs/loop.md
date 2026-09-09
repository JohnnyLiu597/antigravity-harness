# Loop Admission Policy

Recurring, background, multi-agent, or resumed work is admitted only after the
single-task path has reliable contracts and evidence.

Every loop defines:

- trigger and owner;
- task contract and non-goals;
- durable state and resume cursor;
- time, tool, retry, token, and cost budgets;
- file ownership and isolation;
- idempotency and deduplication keys;
- maker-checker boundary;
- verification gate;
- user approval boundary;
- conservative stop conditions.

Unchanged external state is expected and must not cause polling. A repeated
failure without new evidence stops the loop. Scheduled learning is proposal-only
and cannot edit source, install runtime payloads, commit, publish, deploy, or
approve its own recommendations.
