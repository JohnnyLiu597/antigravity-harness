# Safe Observability

Operator-visible events use a deterministic shape:

```json
{
  "status": "success | warning | error | blocked",
  "summary": "one factual sentence",
  "state_transition": "running -> checking",
  "changed_paths": [],
  "exit_code": null,
  "retry_count": 0,
  "next_actions": [],
  "artifacts": [],
  "remaining_uncertainty": []
}
```

The operator must be able to see the objective, phase, changed paths, command
labels, failures, retries, observed side effects, last verified commit, reason
for stopping, and next action. A UI visualization is optional; the JSON evidence
is canonical.

Never persist raw prompts, hidden chain-of-thought, complete commands or tool
output, tokens, cookies, credentials, private session content, or database
contents. Hash sensitive or noisy values and keep only bounded summaries.
