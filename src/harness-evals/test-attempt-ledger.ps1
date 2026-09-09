param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path }

$schemaPath = Join-Path $ProjectRoot "src\schemas\attempt-ledger.schema.json"
$newAttempt = Join-Path $ProjectRoot "src\scripts\new-attempt-record.ps1"
$updateAttempt = Join-Path $ProjectRoot "src\scripts\update-attempt-record.ps1"
$renderReport = Join-Path $ProjectRoot "src\scripts\render-completion-report.ps1"
foreach ($path in @($schemaPath, $newAttempt, $updateAttempt, $renderReport)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Attempt Ledger asset missing: $path" }
}
Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json | Out-Null

function Read-JsonOutput([object[]]$Raw) {
    $text = (@($Raw) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    return $text | ConvertFrom-Json
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (expected '$Expected', got '$Actual')" }
}
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$tmp = Join-Path $env:TEMP ("antigravity-attempt-ledger-" + [guid]::NewGuid().ToString("N"))
$stateRoot = Join-Path $tmp "harness-state"
$workspace = Join-Path $tmp "workspace"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
New-Item -ItemType Directory -Force -Path $workspace | Out-Null
[IO.File]::WriteAllText((Join-Path $workspace "input.txt"), "input-v1`n", (New-Object Text.UTF8Encoding($false)))

try {
    $first = Read-JsonOutput @(& $newAttempt -StateRoot $stateRoot -ProjectRoot $workspace -TaskId "canary-task" -OperationId "runner" -InputPaths @("input.txt") -AttemptId "attempt-1")
    Assert-Equal $first.status "success" "First attempt should be created"
    Assert-Equal $first.ledger_version 1 "First ledger version"
    Assert-True (Test-Path -LiteralPath (Join-Path $stateRoot ".gemini-private")) "Private marker missing"
    $firstLedger = Get-Content -LiteralPath $first.path -Raw | ConvertFrom-Json
    Assert-Equal $firstLedger.producer_script_sha256.Length 64 "Attempt ledger producer hash missing"
    Assert-True ($firstLedger.attempts[0].input_sha256 -ne "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") "Attempt input hash must be observed, not an empty placeholder"
    Assert-Equal $firstLedger.attempts[0].workspace_before_sha256.Length 64 "Workspace-before fingerprint missing"

    $duplicate = Read-JsonOutput @(& $newAttempt -StateRoot $stateRoot -ProjectRoot $workspace -TaskId "canary-task" -OperationId "runner" -InputPaths @("input.txt") -AttemptId "attempt-1")
    Assert-Equal $duplicate.status "error" "Duplicate attempt ID must be rejected"
    Assert-Equal $duplicate.error_code "attempt_id_conflict" "Duplicate attempt error code"

    $missingEvidence = Read-JsonOutput @(& $updateAttempt -LedgerPath $first.path -AttemptId "attempt-1" -ExpectedVersion 1 -Status "failed" -ExitCode 1 -FailureClass "assumption-error" -RecoveryAction "Read the actual output contract" -EvidenceArtifact "artifacts/missing-attempt.json")
    Assert-Equal $missingEvidence.status "error" "Missing evidence artifact must be rejected"
    Assert-Equal $missingEvidence.error_code "evidence_artifact_missing" "Missing evidence error code"
    New-Item -ItemType Directory -Force -Path (Join-Path $workspace "artifacts") | Out-Null
    [IO.File]::WriteAllText((Join-Path $workspace "artifacts\attempt-1.json"), "{}`n", (New-Object Text.UTF8Encoding($false)))
    $failed = Read-JsonOutput @(& $updateAttempt -LedgerPath $first.path -AttemptId "attempt-1" -ExpectedVersion 1 -Status "failed" -ExitCode 1 -FailureClass "assumption-error" -SideEffectsObserved -RecoveryAction "Read the actual output contract" -EvidenceArtifact "artifacts/attempt-1.json")
    Assert-Equal $failed.status "success" "Failed attempt should be recorded"
    Assert-Equal $failed.ledger_version 2 "Failed update version"

    $second = Read-JsonOutput @(& $newAttempt -StateRoot $stateRoot -ProjectRoot $workspace -TaskId "canary-task" -OperationId "runner" -InputPaths @("input.txt") -AttemptId "attempt-2" -ExpectedVersion 2)
    Assert-Equal $second.status "success" "Retry attempt should be created"
    Assert-Equal $second.attempt_sequence 2 "Retry sequence"

    [IO.File]::WriteAllText((Join-Path $workspace "output.txt"), "created`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $workspace "artifacts\attempt-2.json"), "{}`n", (New-Object Text.UTF8Encoding($false)))
    $passed = Read-JsonOutput @(& $updateAttempt -LedgerPath $first.path -AttemptId "attempt-2" -ExpectedVersion 3 -Status "passed" -ExitCode 0 -RecoveryAction "Corrected the field name" -EvidenceArtifact "artifacts/attempt-2.json")
    Assert-Equal $passed.status "success" "Second attempt should pass"
    $observedLedger = Get-Content -LiteralPath $first.path -Raw | ConvertFrom-Json
    Assert-Equal $observedLedger.last_update_script_sha256.Length 64 "Attempt update producer hash missing"
    Assert-Equal $observedLedger.attempts[1].side_effects_observed $true "File creation must be observed as a side effect"
    Assert-True (@($observedLedger.attempts[1].changed_paths) -contains "output.txt") "Created file missing from changed paths"
    Assert-Equal $observedLedger.attempts[1].evidence_sha256.Length 64 "Evidence artifact hash missing"

    $emptyWorkspace = Join-Path $tmp "empty-workspace"
    $emptyStateRoot = Join-Path $tmp "empty-state"
    New-Item -ItemType Directory -Force -Path $emptyWorkspace | Out-Null
    $emptyAttempt = Read-JsonOutput @(& $newAttempt -StateRoot $emptyStateRoot -ProjectRoot $emptyWorkspace -TaskId "empty-failure-task" -OperationId "failed-write" -AttemptId "empty-attempt-1")
    [IO.File]::WriteAllText((Join-Path $emptyWorkspace "failed-side-effect.txt"), "created before failure`n", (New-Object Text.UTF8Encoding($false)))
    New-Item -ItemType Directory -Force -Path (Join-Path $emptyWorkspace "artifacts") | Out-Null
    [IO.File]::WriteAllText((Join-Path $emptyWorkspace "artifacts\empty-failure.json"), "{}`n", (New-Object Text.UTF8Encoding($false)))
    $emptyFailed = Read-JsonOutput @(& $updateAttempt -LedgerPath $emptyAttempt.path -AttemptId "empty-attempt-1" -ExpectedVersion 1 -Status "failed" -ExitCode 1 -FailureClass "test-failure" -RecoveryAction "Inspect the failed side effect" -EvidenceArtifact "artifacts/empty-failure.json")
    Assert-Equal $emptyFailed.status "success" "Empty-workspace failed attempt should close"
    $emptyLedger = Get-Content -LiteralPath $emptyAttempt.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $emptyLedger.attempts[0].workspace_after_sha256.Length 64 "Empty-workspace failure must retain a workspace-after fingerprint"
    Assert-True (@($emptyLedger.attempts[0].changed_paths) -contains "failed-side-effect.txt") "Failed attempt did not observe the created file"
    Assert-Equal $emptyLedger.attempts[0].side_effects_observed $true "Failed attempt side effect must not disappear"

    $terminalMutation = Read-JsonOutput @(& $updateAttempt -LedgerPath $first.path -AttemptId "attempt-1" -ExpectedVersion 4 -Status "passed" -ExitCode 0)
    Assert-Equal $terminalMutation.status "error" "Terminal attempt must be immutable"
    Assert-Equal $terminalMutation.error_code "attempt_terminal" "Terminal mutation error code"

    $rendered = Read-JsonOutput @(& $renderReport -LedgerPath $first.path)
    Assert-Equal $rendered.status "success" "Completion report should render"
    Assert-Equal $rendered.report_status "passed_after_retry" "Failure history must affect final status"
    $reportRaw = Get-Content -LiteralPath $rendered.report -Raw
    $report = $reportRaw | ConvertFrom-Json
    Assert-Equal $report.producer_script_sha256.Length 64 "Completion report producer hash missing"
    Assert-Equal $report.attempt_count 2 "Report must include every attempt"
    Assert-Equal $report.failed_count 1 "Report must retain the failed attempt"
    Assert-Equal $report.attempts[0].failure_class "assumption-error" "Failure class missing"
    Assert-True ($reportRaw -match "Read the actual output contract") "Recovery action missing"
    Assert-True ($reportRaw -notmatch '(?i)raw_prompt|raw_output|hidden_reasoning|chain_of_thought') "Forbidden raw fields entered report"

    $running = Read-JsonOutput @(& $newAttempt -StateRoot $stateRoot -ProjectRoot $workspace -TaskId "unfinished-task" -OperationId "work" -InputPaths @("input.txt") -AttemptId "running-1")
    $unfinished = Read-JsonOutput @(& $renderReport -LedgerPath $running.path)
    Assert-Equal $unfinished.status "error" "Running attempts must block final report"
    Assert-Equal $unfinished.error_code "attempts_incomplete" "Incomplete report error code"

    [ordered]@{
        status = "success"
        summary = "Attempt Ledger preserves failures and deterministically renders passed_after_retry without raw payloads."
        cases = @("create", "duplicate", "failure", "retry", "terminal-immutability", "report-completeness", "incomplete-block")
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
