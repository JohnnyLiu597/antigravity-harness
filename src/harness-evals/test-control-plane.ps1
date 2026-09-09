param(
    [string]$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$TestRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TestRoot)) {
    # Native state writes append IDs, SHA-256 names and atomic temporary suffixes.
    # Keep fixture paths short enough for Windows PowerShell/.NET MAX_PATH.
    # Do not move this suite into TEMP: TEMP is intentionally an allowed state
    # root, which would invalidate the negative product-source placement case.
    $runId = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $TestRoot = Join-Path $ProjectRoot ("artifacts\cp-" + $runId)
}

New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
$workspace = Join-Path $TestRoot "workspace"
$stateRoot = Join-Path $workspace "artifacts\harness-state"
New-Item -ItemType Directory -Force -Path (Join-Path $workspace "src\secrets") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $workspace "tests") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $workspace "artifacts") | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $workspace "src\app.ps1"), "'v1'`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $workspace "tests\app.tests.ps1"), "'test'`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $workspace "artifacts\ignored.txt"), "ignored-v1`n", $utf8NoBom)

$scriptsRoot = Join-Path $ProjectRoot "src\scripts"
$schemasRoot = Join-Path $ProjectRoot "src\schemas"
$templatesRoot = Join-Path $ProjectRoot "src\templates"
$newContractScript = Join-Path $scriptsRoot "new-task-contract.ps1"
$scopeScript = Join-Path $scriptsRoot "test-task-scope.ps1"
$newJobScript = Join-Path $scriptsRoot "new-job-state.ps1"
$updateJobScript = Join-Path $scriptsRoot "update-job-state.ps1"
$fingerprintScript = Join-Path $scriptsRoot "get-workspace-fingerprint.ps1"
$safeCommandScript = Join-Path $scriptsRoot "invoke-safe-command.ps1"
$newGovernedTaskScript = Join-Path $scriptsRoot "new-governed-task.ps1"

$results = New-Object System.Collections.Generic.List[object]
$passedCount = 0
$failedCount = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )
    if ($Actual -ne $Expected) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-Contains {
    param(
        [object[]]$Collection,
        $Expected,
        [string]$Message
    )
    if ($Expected -notin @($Collection)) {
        throw "$Message (missing '$Expected')"
    }
}

function ConvertFrom-ScriptJson {
    param([object[]]$Raw)
    $text = (@($Raw) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Script returned no JSON output." }
    try {
        return $text | ConvertFrom-Json
    } catch {
        throw "Script returned invalid JSON: $text"
    }
}

function Invoke-ControlCase {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $started = Get-Date
    try {
        & $Action
        $script:passedCount++
        $results.Add([pscustomobject]@{
            name = $Name
            status = "passed"
            duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
            error = $null
        }) | Out-Null
    } catch {
        $script:failedCount++
        $results.Add([pscustomobject]@{
            name = $Name
            status = "failed"
            duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
            error = $_.Exception.Message
        }) | Out-Null
    }
}

$script:contractPath = $null
$script:jobPath = $null

Invoke-ControlCase -Name "required-assets-and-json-schemas" -Action {
    $requiredFiles = @(
        (Join-Path $schemasRoot "task-contract.schema.json"),
        (Join-Path $schemasRoot "job-state.schema.json"),
        (Join-Path $schemasRoot "tool-event.schema.json"),
        (Join-Path $templatesRoot "task-contract.template.json"),
        $newContractScript,
        $scopeScript,
        $newJobScript,
        $updateJobScript,
        $fingerprintScript,
        $safeCommandScript
        $newGovernedTaskScript
    )
    $missing = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    Assert-Equal -Actual $missing.Count -Expected 0 -Message ("Missing control-plane assets: " + ($missing -join ", "))

    foreach ($path in @($requiredFiles | Where-Object { $_ -like "*.json" })) {
        Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    }
}

Invoke-ControlCase -Name "empty-workspace-contract-baseline" -Action {
    $emptyWorkspace = Join-Path $env:TEMP ("antigravity-empty-contract-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $emptyWorkspace | Out-Null
    $emptyState = Join-Path $emptyWorkspace "harness-state"
    $created = ConvertFrom-ScriptJson -Raw @(& $newContractScript `
        -ProjectRoot $emptyWorkspace `
        -StateRoot $emptyState `
        -Objective "Create a contract without a dummy file" `
        -AllowedPaths @("docs/output.md") `
        -ContractId "empty-workspace-contract")
    Assert-Equal $created.status "success" "An empty project must not require a dummy README"
    $contract = Get-Content -LiteralPath $created.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal @($contract.baseline.files).Count 0 "Empty workspace baseline must serialize as an empty array"
    Assert-Equal $contract.baseline.workspace_sha256.Length 64 "Empty workspace baseline must still have a fingerprint"
}

Invoke-ControlCase -Name "governed-task-root-requires-explicit-transition" -Action {
    $governedTestRoot = Join-Path $env:TEMP ("antigravity-governed-root-test-" + [guid]::NewGuid().ToString("N"))
    $registryRoot = Join-Path $governedTestRoot "task-root-registry"
    $firstRoot = Join-Path $governedTestRoot "governed-root-one"
    $secondRoot = Join-Path $governedTestRoot "governed-root-two"
    New-Item -ItemType Directory -Force -Path $firstRoot, $secondRoot | Out-Null
    $first = ConvertFrom-ScriptJson -Raw @(& $newGovernedTaskScript -ProjectRoot $firstRoot -RegistryRoot $registryRoot -LogicalTaskId "logical-task-one" -Objective "One logical task" -AllowedPaths @("docs/output.md"))
    Assert-Equal $first.status "success" "First governed task root should be created"
    Assert-True (Test-Path -LiteralPath $first.manifest -PathType Leaf) "Governed task root manifest missing"
    Assert-True (Test-Path -LiteralPath (Join-Path $registryRoot ".gemini-private") -PathType Leaf) "Task registry must be marked private"

    $changedIdSwitch = ConvertFrom-ScriptJson -Raw @(& $newGovernedTaskScript -ProjectRoot $secondRoot -RegistryRoot $registryRoot -LogicalTaskId "renamed-logical-task" -Objective "One logical task" -AllowedPaths @("docs/output.md"))
    Assert-Equal $changedIdSwitch.status "error" "Changing LogicalTaskId must not evade an active identical task intent"
    Assert-Equal $changedIdSwitch.error_code "task_intent_already_active" "Cross-ID task intent collision must be explicit"
    Assert-Equal $changedIdSwitch.existing_logical_task_id "logical-task-one" "Task intent collision must identify the resumable logical task"

    $silentSwitch = ConvertFrom-ScriptJson -Raw @(& $newGovernedTaskScript -ProjectRoot $secondRoot -RegistryRoot $registryRoot -LogicalTaskId "logical-task-one" -Objective "One logical task" -AllowedPaths @("docs/output.md"))
    Assert-Equal $silentSwitch.status "error" "A silent TaskRoot switch must be rejected"
    Assert-Equal $silentSwitch.error_code "task_root_transition_required" "Silent TaskRoot switch must name the transition requirement"

    $transition = ConvertFrom-ScriptJson -Raw @(& $newGovernedTaskScript -ProjectRoot $secondRoot -RegistryRoot $registryRoot -LogicalTaskId "logical-task-one" -Objective "One logical task" -AllowedPaths @("docs/output.md") -PreviousTaskRoot $firstRoot -TransitionReason "bootstrap recovery after recorded failure")
    Assert-Equal $transition.status "success" "An explicitly linked TaskRoot transition should succeed"
    $manifest = Get-Content -LiteralPath $transition.manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $manifest.generation 2 "Linked TaskRoot transition must increment generation"
    Assert-Equal $manifest.previous_task_root_sha256.Length 64 "Linked TaskRoot transition must retain the prior root hash"
}

Invoke-ControlCase -Name "task-contract-creation-and-private-state" -Action {
    $unsafeStateRoot = Join-Path $workspace "src\unsafe-harness-state"
    $unsafeRaw = & $newContractScript `
        -ProjectRoot $workspace `
        -StateRoot $unsafeStateRoot `
        -Objective "Unsafe state placement" `
        -AllowedPaths @("src/")
    $unsafe = ConvertFrom-ScriptJson -Raw @($unsafeRaw)
    Assert-Equal $unsafe.status "error" "Task contract must reject state inside product source"
    Assert-True (-not (Test-Path -LiteralPath $unsafeStateRoot)) "Unsafe state root was created inside product source"

    $raw = & $newContractScript `
        -ProjectRoot $workspace `
        -StateRoot $stateRoot `
        -Objective "Limit a local repair to the approved source surface" `
        -NonGoals @("No dependency replacement", "No architecture redesign") `
        -AllowedPaths @("src/", "tests/") `
        -DeniedPaths @("src/secrets/") `
        -MaxFiles 2 `
        -MaxAddedLines 10 `
        -RequiredChecks @("targeted-test", "syntax") `
        -ApprovalTriggers @("scope_expansion", "dependency_change", "architecture_change")
    $result = ConvertFrom-ScriptJson -Raw @($raw)
    Assert-Equal $result.status "success" "Task contract creation should succeed"
    Assert-True (Test-Path -LiteralPath $result.path -PathType Leaf) "Task contract file was not created"
    Assert-True (Test-Path -LiteralPath (Join-Path $stateRoot ".gemini-private") -PathType Leaf) "Private marker was not created"

    $contract = Get-Content -LiteralPath $result.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $contract.schema "antigravity-harness-task-contract-v2" "Unexpected task contract schema"
    Assert-Equal $contract.producer_script_sha256.Length 64 "Task contract producer hash missing"
    Assert-Equal $contract.scope.access "write" "Task contract should default to write access"
    Assert-Contains @($contract.scope.allowed_paths) "src/" "Allowed paths were not retained"
    Assert-Contains @($contract.scope.denied_paths) "src/secrets/" "Denied paths were not retained"
    Assert-Equal $contract.change_budget.max_files 2 "File budget was not retained"
    Assert-Equal $contract.change_budget.max_added_lines 10 "Line budget was not retained"
    Assert-Equal $contract.change_budget.dependency_changes $false "Dependency budget should default to denied"
    Assert-Equal $contract.change_budget.architecture_changes $false "Architecture budget should default to denied"
    Assert-Contains @($contract.approval_triggers) "scope_expansion" "Approval triggers were not retained"
    Assert-Equal $contract.baseline.workspace_sha256.Length 64 "Task contract baseline fingerprint missing"
    Assert-True ($contract.baseline.files.Count -gt 0) "Task contract baseline file snapshot missing"

    $serialized = $contract | ConvertTo-Json -Depth 10 -Compress
    Assert-True ($serialized -notmatch '(?i)raw[_-]?prompt|chain[_-]?of[_-]?thought|hidden[_-]?reason') "Contract contains forbidden reasoning/prompt fields"
    $script:contractPath = $result.path
}

Invoke-ControlCase -Name "scope-accepts-authorized-change" -Action {
    Assert-True (-not [string]::IsNullOrWhiteSpace($script:contractPath)) "Contract setup did not complete"
    $raw = & $scopeScript -ContractPath $script:contractPath -ChangedPaths @("src/app.ps1", "tests/app.tests.ps1") -AddedLines 9
    $result = ConvertFrom-ScriptJson -Raw @($raw)
    Assert-Equal $result.status "passed" "Authorized change should pass scope validation"
    Assert-Equal $result.assessment_mode "pre_write_declared" "Caller-declared scope data must be labelled as a pre-write declaration"
    Assert-Equal $result.allowed $true "Authorized change should be allowed"
    Assert-Equal @($result.violations).Count 0 "Authorized change should have no violations"
}

Invoke-ControlCase -Name "scope-blocks-denied-and-outside-paths" -Action {
    $raw = & $scopeScript -ContractPath $script:contractPath -ChangedPaths @("src/secrets/token.txt", "docs/unplanned.md") -AddedLines 2
    $result = ConvertFrom-ScriptJson -Raw @($raw)
    Assert-Equal $result.status "waiting_approval" "Out-of-scope paths should require approval"
    Assert-Equal $result.allowed $false "Out-of-scope paths should be blocked"
    $types = @($result.violations | ForEach-Object { $_.type })
    Assert-Contains $types "denied_path" "Denied path violation was not reported"
    Assert-Contains $types "outside_allowed_paths" "Outside allowlist violation was not reported"
    Assert-Contains @($result.required_approval_triggers) "scope_expansion" "Scope expansion trigger was not requested"
}

Invoke-ControlCase -Name "scope-enforces-file-line-dependency-and-architecture-budgets" -Action {
    $raw = & $scopeScript `
        -ContractPath $script:contractPath `
        -ChangedPaths @("src/a.ps1", "src/b.ps1", "tests/c.tests.ps1") `
        -AddedLines 11 `
        -DependencyChanged `
        -ArchitectureChanged
    $result = ConvertFrom-ScriptJson -Raw @($raw)
    Assert-Equal $result.status "waiting_approval" "Budget excess should require approval"
    $types = @($result.violations | ForEach-Object { $_.type })
    foreach ($expected in @("max_files_exceeded", "max_added_lines_exceeded", "dependency_change_denied", "architecture_change_denied")) {
        Assert-Contains $types $expected "Budget violation was not reported"
    }
    Assert-Contains @($result.required_approval_triggers) "dependency_change" "Dependency approval trigger was not requested"
    Assert-Contains @($result.required_approval_triggers) "architecture_change" "Architecture approval trigger was not requested"
}

Invoke-ControlCase -Name "scope-observes-real-workspace-delta" -Action {
    $observedWorkspace = Join-Path $TestRoot "observed-workspace"
    New-Item -ItemType Directory -Force -Path (Join-Path $observedWorkspace "src"), (Join-Path $observedWorkspace "artifacts") | Out-Null
    [IO.File]::WriteAllText((Join-Path $observedWorkspace "src\base.ps1"), "'base'`n", $utf8NoBom)
    $observedState = Join-Path $observedWorkspace "artifacts\harness-state"
    $observedContractResult = ConvertFrom-ScriptJson -Raw @(& $newContractScript -ProjectRoot $observedWorkspace -StateRoot $observedState -Objective "Observe actual delta" -AllowedPaths @("docs/") -DeniedPaths @("config/") -MaxFiles 2 -MaxAddedLines 5)
    [IO.Directory]::CreateDirectory((Join-Path $observedWorkspace "docs")) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $observedWorkspace "config")) | Out-Null
    [IO.File]::WriteAllText((Join-Path $observedWorkspace "docs\new.md"), "one`ntwo`nthree`n", $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $observedWorkspace "config\secret.txt"), "blocked`n", $utf8NoBom)
    $observed = ConvertFrom-ScriptJson -Raw @(& $scopeScript -ContractPath $observedContractResult.path -ObserveWorkspace)
    Assert-Equal $observed.metrics.source "contract-baseline" "Scope metrics must come from observed baseline delta"
    Assert-Equal $observed.assessment_mode "post_write_observed" "Observed workspace scope must be labelled as a post-write audit"
    Assert-Contains @($observed.metrics.changed_paths) "docs/new.md" "Observed allowed file missing"
    Assert-Contains @($observed.metrics.changed_paths) "config/secret.txt" "Observed denied file missing"
    Assert-Equal $observed.metrics.added_lines 4 "Observed added lines must be calculated from files"
    Assert-Contains @($observed.violations | ForEach-Object { $_.type }) "denied_path" "Observed denied path not blocked"
}

Invoke-ControlCase -Name "job-state-allows-only-evidence-bearing-monotonic-transitions" -Action {
    $raw = & $newJobScript -ContractPath $script:contractPath -StateRoot $stateRoot -JobId "control-plane-green-path"
    $created = ConvertFrom-ScriptJson -Raw @($raw)
    Assert-Equal $created.status "success" "Job creation should succeed"
    Assert-Equal $created.state "drafted" "New job should start drafted"
    Assert-Equal $created.version 1 "New job version should start at one"
    $script:jobPath = $created.path

    $approved = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $script:jobPath -ToState "approved" -ExpectedVersion 1 -ProgressSummary "Contract approved")
    Assert-Equal $approved.state "approved" "Drafted job should transition to approved"
    Assert-Equal $approved.version 2 "Approved transition should increment version"

    $running = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $script:jobPath -ToState "running" -ExpectedVersion 2 -ProgressSummary "Bounded execution started" -NextAction "Run the targeted implementation step")
    Assert-Equal $running.state "running" "Approved job should transition to running"

    $checking = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $script:jobPath -ToState "checking" -ExpectedVersion 3 -ProgressSummary "Implementation complete" -NextAction "Verify current workspace" -WorkspaceFingerprint ("a" * 64))
    Assert-Equal $checking.state "checking" "Running job should transition to checking"

    $verified = ConvertFrom-ScriptJson -Raw @(& $updateJobScript `
        -JobPath $script:jobPath `
        -ToState "verified" `
        -ExpectedVersion 4 `
        -ProgressSummary "Independent checks passed" `
        -StopReason "completion_gate_passed" `
        -VerifiedCommit "abc1234" `
        -WorkspaceFingerprint ("b" * 64) `
        -VerificationArtifact "verification/control-plane.json")
    Assert-Equal $verified.state "verified" "Checking job with evidence should transition to verified"
    Assert-Equal $verified.version 5 "Verified transition should increment version"

    $job = Get-Content -LiteralPath $script:jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $job.history.Count 5 "Every state transition should be recorded"
    Assert-Equal $job.verification.workspace_fingerprint ("b" * 64) "Verification fingerprint was not retained"
    Assert-Equal $job.verification.artifact "verification/control-plane.json" "Verification artifact was not retained"
}

Invoke-ControlCase -Name "job-state-rejects-skipped-stale-and-terminal-transitions" -Action {
    $created = ConvertFrom-ScriptJson -Raw @(& $newJobScript -ContractPath $script:contractPath -StateRoot $stateRoot -JobId "control-plane-rejections")
    $jobPath = $created.path

    $skipped = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $jobPath -ToState "verified" -ExpectedVersion 1 -WorkspaceFingerprint ("c" * 64) -VerificationArtifact "verification/invalid.json" -VerifiedCommit "def5678")
    Assert-Equal $skipped.status "error" "Skipped transition should be rejected"
    Assert-Equal $skipped.error_code "invalid_transition" "Skipped transition should report invalid_transition"

    $approved = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $jobPath -ToState "approved" -ExpectedVersion 1)
    Assert-Equal $approved.status "success" "Job should still be drafted after rejected transition"

    $stale = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $jobPath -ToState "running" -ExpectedVersion 1)
    Assert-Equal $stale.status "error" "Stale version should be rejected"
    Assert-Equal $stale.error_code "version_conflict" "Stale transition should report version_conflict"

    $stopped = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $jobPath -ToState "stopped" -ExpectedVersion 2 -StopReason "user_requested")
    Assert-Equal $stopped.state "stopped" "Approved job should be stoppable"

    $terminal = ConvertFrom-ScriptJson -Raw @(& $updateJobScript -JobPath $jobPath -ToState "running" -ExpectedVersion 3)
    Assert-Equal $terminal.status "error" "Terminal job should not restart"
    Assert-Equal $terminal.error_code "terminal_state" "Terminal transition should report terminal_state"
}

Invoke-ControlCase -Name "workspace-fingerprint-is-content-bound-and-ignores-artifacts" -Action {
    $first = ConvertFrom-ScriptJson -Raw @(& $fingerprintScript -ProjectRoot $workspace)
    Assert-Equal $first.status "success" "Initial fingerprint should succeed"
    Assert-Equal $first.fingerprint_sha256.Length 64 "Fingerprint should be a SHA-256 hex digest"

    [System.IO.File]::WriteAllText((Join-Path $workspace "artifacts\ignored.txt"), "ignored-v2`n", $utf8NoBom)
    $artifactOnly = ConvertFrom-ScriptJson -Raw @(& $fingerprintScript -ProjectRoot $workspace)
    Assert-Equal $artifactOnly.fingerprint_sha256 $first.fingerprint_sha256 "Ignored artifact change should not invalidate source fingerprint"

    [System.IO.File]::WriteAllText((Join-Path $workspace "src\app.ps1"), "'v2'`n", $utf8NoBom)
    $sourceChange = ConvertFrom-ScriptJson -Raw @(& $fingerprintScript -ProjectRoot $workspace)
    Assert-True ($sourceChange.fingerprint_sha256 -ne $first.fingerprint_sha256) "Source change should invalidate fingerprint"
}

Invoke-ControlCase -Name "safe-command-preserves-exit-timeout-hashes-and-idempotency" -Action {
    $hostExecutable = (Get-Process -Id $PID).Path
    $successArgs = @("-NoProfile", "-Command", "Write-Output 'control-plane-output'; exit 0")
    $success = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList $successArgs `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 5 `
        -OperationId "safe-success" `
        -IdempotencyKey "safe-success-key" `
        -StateRoot $stateRoot)
    $successErrorType = if ($success.PSObject.Properties.Name -contains "error_type") { $success.error_type } else { "none" }
    Assert-Equal $success.status "succeeded" "Successful command should be reported as succeeded (error_code=$($success.error_code); error_type=$successErrorType)"
    Assert-Equal $success.executed $true "First successful command should execute"
    Assert-Equal $success.exit_code 0 "Successful command exit code should be preserved"
    Assert-Equal $success.stdout_sha256.Length 64 "stdout should be represented by a SHA-256 digest"
    Assert-True (-not ($success.PSObject.Properties.Name -contains "stdout")) "Full stdout must not be returned"
    Assert-True (-not ($success.PSObject.Properties.Name -contains "stderr")) "Full stderr must not be returned"

    $duplicate = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList $successArgs `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 5 `
        -OperationId "safe-success" `
        -IdempotencyKey "safe-success-key" `
        -StateRoot $stateRoot)
    Assert-Equal $duplicate.status "already_satisfied" "Successful idempotent operation should not run twice"
    Assert-Equal $duplicate.executed $false "Duplicate successful operation should not execute"
    Assert-Equal $duplicate.duplicate_prevented $true "Duplicate prevention should be explicit"

    $conflict = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList @("-NoProfile", "-Command", "exit 0") `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 5 `
        -OperationId "safe-success" `
        -IdempotencyKey "safe-success-key" `
        -StateRoot $stateRoot)
    Assert-Equal $conflict.status "blocked" "Reusing an idempotency key for a different command should be blocked"
    Assert-Equal $conflict.error_code "idempotency_conflict" "Idempotency conflict should be explicit"

    $failureEffect = Join-Path $workspace "failure-effect.txt"
    $escapedFailureEffect = $failureEffect.Replace("'", "''")
    $failureArgs = @("-NoProfile", "-Command", "Add-Content -LiteralPath '$escapedFailureEffect' -Value 'effect'; exit 7")
    $failure = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList $failureArgs `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 5 `
        -OperationId "safe-failure" `
        -IdempotencyKey "safe-failure-key" `
        -StateRoot $stateRoot)
    Assert-Equal $failure.status "failed" "Non-zero child exit should fail"
    Assert-Equal $failure.exit_code 7 "Real child exit code should be preserved"

    $failureRetry = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList $failureArgs `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 5 `
        -OperationId "safe-failure" `
        -IdempotencyKey "safe-failure-key" `
        -StateRoot $stateRoot)
    Assert-Equal $failureRetry.status "blocked" "Failed side effect should require reconciliation before retry"
    Assert-Equal $failureRetry.error_code "previous_attempt_uncertain" "Failed side-effect retry should be explicitly uncertain"
    Assert-Equal @(Get-Content -LiteralPath $failureEffect).Count 1 "Failed side effect executed more than once"

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $timeout = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList @("-NoProfile", "-Command", "[System.Threading.Thread]::Sleep(3000); exit 0") `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 1 `
        -OperationId "safe-timeout" `
        -IdempotencyKey "safe-timeout-key" `
        -StateRoot $stateRoot)
    $timer.Stop()
    Assert-Equal $timeout.status "timed_out" "Timeout should be explicit"
    Assert-Equal $timeout.timed_out $true "Timeout flag should be true"
    Assert-True ($timer.Elapsed.TotalSeconds -lt 8) "Timeout guard did not stop within a bounded interval"

    $timeoutRetry = ConvertFrom-ScriptJson -Raw @(& $safeCommandScript `
        -FilePath $hostExecutable `
        -ArgumentList @("-NoProfile", "-Command", "[System.Threading.Thread]::Sleep(3000); exit 0") `
        -WorkingDirectory $workspace `
        -TimeoutSeconds 1 `
        -OperationId "safe-timeout" `
        -IdempotencyKey "safe-timeout-key" `
        -StateRoot $stateRoot)
    Assert-Equal $timeoutRetry.status "blocked" "Timed-out side effect should require reconciliation before retry"
    Assert-Equal $timeoutRetry.error_code "previous_attempt_uncertain" "Uncertain retry should be explicit"

    Assert-True (Test-Path -LiteralPath $success.event_path -PathType Leaf) "Tool event evidence was not written"
    $storedEventText = Get-Content -LiteralPath $success.event_path -Raw -Encoding UTF8
    $storedEvent = $storedEventText | ConvertFrom-Json
    Assert-Equal $storedEvent.schema "antigravity-harness-tool-event-v2" "Unexpected tool event schema"
    Assert-Equal $storedEvent.command_fingerprint.Length 64 "Stored command fingerprint should be SHA-256"
    Assert-Equal $storedEvent.idempotency_key_sha256.Length 64 "Stored idempotency key should be hashed"
    Assert-True ($storedEventText -notmatch 'control-plane-output|Write-Output') "Stored event must not contain full command output or raw command arguments"
}

$summary = [ordered]@{
    schema = "antigravity-harness-control-plane-tests-v2"
    status = if ($failedCount -eq 0) { "passed" } else { "failed" }
    project_root = $ProjectRoot
    test_root = $TestRoot
    passed = $passedCount
    failed = $failedCount
    cases = $results.ToArray()
}

$summaryJson = $summary | ConvertTo-Json -Depth 8 -Compress
Write-Output $summaryJson

if ($failedCount -gt 0) {
    throw "Control-plane tests failed: $failedCount case(s). Evidence: $TestRoot"
}
