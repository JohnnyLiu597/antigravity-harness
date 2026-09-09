# Antigravity Harness Behavioral Evals

Run the deterministic source regression owner:

```powershell
.\src\harness-evals\run-harness-evals.ps1
```

The runner executes truth-registry, bounded-control, attempt-truth,
causal-verification, governance, package-integration, gate-integration,
project-scaffold, and getting-started documentation cases.
It stores only case status, exit codes, durations, and output hashes in ignored
run artifacts; raw test output is not persisted by the runner.

These tests verify harness code and contracts. They do not prove that in-app
Antigravity tools, model routing, lifecycle interception, or reactive wakeup are
available. Those claims require a separate live canary under the same task,
permission, model, network, and timeout conditions used for baseline comparison.
