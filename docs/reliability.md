# Reliability Policy

The harness raises Antigravity's reliability floor by constraining effects and
externalizing state. It does not claim to remove model, quota, service, or tool
failures.

## Failure Workflow

1. Reproduce the target problem when feasible.
2. State one falsifiable hypothesis and its predicted evidence.
3. Run the smallest diagnostic that can reject the hypothesis.
4. Change one variable.
5. Rerun the original reproduction.
6. Classify the result as task-caused, pre-existing, environment, permission,
   timeout, tool-defect, assumption-error, or insufficient-evidence.

The same deterministic failure must not be retried blindly. A failed, timed-out,
or interrupted operation with possible side effects is uncertain and cannot be
re-executed with the same idempotency key until external state is reconciled.
Three failed strategies move the job to `blocked` or `waiting_approval`.

## Scope Reliability

Non-trivial writes require a task contract. An edit outside allowed paths, a
dependency change, a budget overrun, a migration, deployment, publication, or
destructive effect requires explicit user approval.

Task Contract creation records a baseline snapshot. `test-task-scope.ps1
-ObserveWorkspace` derives changed paths and added lines from that baseline;
caller-supplied counts are compatibility inputs, not completion evidence.
The empty workspace is supported and hashes a canonical empty array rather
than requiring a placeholder file.

One logical task should be created through `new-governed-task.ps1`. Its private
registry rejects a second active TaskRoot unless the caller supplies the prior
root and a transition reason. This prevents an ordinary retry from silently
discarding the earlier Attempt Ledger.
The registry independently indexes normalized task intent. Changing a
timestamped LogicalTaskId while keeping the same objective, scope, checks, and
budgets returns `task_intent_already_active` and identifies the task to resume.

Attempt scripts derive input hashes, workspace-before/after hashes, changed
paths, and observed side effects. Terminal attempts require a real evidence
artifact whose SHA-256 is rechecked by the Completion Gate.
An empty `workspace_before` array is valid evidence, not a reason to skip the
workspace-after snapshot. Completion fails closed when a terminal Attempt has
no after fingerprint, when fingerprints differ without changed paths, or when
changed paths are present while side effects are reported false.

## Privacy

Evidence stores hashes, counts, timestamps, paths, exit codes, and bounded
summaries. It never stores raw prompts, hidden reasoning, secrets, cookies,
credentials, or complete tool output.
