param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$requiredFiles = @(
    "src\schemas\verification-envelope.schema.json",
    "src\schemas\completion-claim.schema.json",
    "src\scripts\detect-project-test-surface.ps1",
    "src\scripts\invoke-verification-envelope.ps1",
    "src\scripts\invoke-completion-gate.ps1",
    "src\scripts\new-completion-claim.ps1",
    "src\scripts\new-attempt-record.ps1",
    "src\scripts\update-attempt-record.ps1",
    "src\scripts\render-completion-report.ps1"
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Verification-plane implementation missing: $relativePath"
    }
}

$detectScript = Join-Path $ProjectRoot "src\scripts\detect-project-test-surface.ps1"
$envelopeScript = Join-Path $ProjectRoot "src\scripts\invoke-verification-envelope.ps1"
$completionScript = Join-Path $ProjectRoot "src\scripts\invoke-completion-gate.ps1"
$claimProducerScript = Join-Path $ProjectRoot "src\scripts\new-completion-claim.ps1"
$newAttemptScript = Join-Path $ProjectRoot "src\scripts\new-attempt-record.ps1"
$updateAttemptScript = Join-Path $ProjectRoot "src\scripts\update-attempt-record.ps1"
$renderAttemptReportScript = Join-Path $ProjectRoot "src\scripts\render-completion-report.ps1"

function Write-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Value = ""
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Assert-True {
    param(
        [bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ExpectedFailure {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $caught = $false
    $script:lastExpectedFailure = ""
    try {
        & $Action | Out-Null
    } catch {
        $caught = $true
        $script:lastExpectedFailure = $_.Exception.Message
    }
    if (-not $caught) {
        throw $Message
    }
}

function Get-LatestJsonArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativeArtifactRoot,
        [Parameter(Mandatory = $true)][string]$FileName,
        [string]$DirectoryContains = ""
    )

    $artifactRoot = Join-Path $Root $RelativeArtifactRoot
    $items = Get-ChildItem -LiteralPath $artifactRoot -Recurse -Filter $FileName -File -ErrorAction SilentlyContinue
    if ($DirectoryContains) {
        $items = @($items | Where-Object { $_.Directory.Name -like "*$DirectoryContains*" })
    }
    $item = $items |
        Sort-Object @{ Expression = { $_.Directory.Name }; Descending = $true }, @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true } |
        Select-Object -First 1
    if (-not $item) {
        $observed = @(Get-ChildItem -LiteralPath $artifactRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        throw "Expected artifact was not created: $RelativeArtifactRoot\$FileName (filter='$DirectoryContains'; observed='$($observed -join ',')'; failure='$script:lastExpectedFailure')"
    }
    return [pscustomobject]@{
        path = $item.FullName
        raw = Get-Content -LiteralPath $item.FullName -Raw
        value = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
    }
}

function Write-CompletionClaim {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ActorRole,
        [Parameter(Mandatory = $true)][string]$RequestedStatus,
        [Parameter(Mandatory = $true)][string]$EnvelopePath,
        [Parameter(Mandatory = $true)][string]$EnvelopeSha256,
        [bool]$Independent = $true,
        [string]$CheckerRole = "",
        [string]$AcceptanceEvidenceSha256 = "",
        [string]$CriterionId = "fixture-tests"
    )

    if (-not $CheckerRole) { $CheckerRole = $ActorRole }
    if (-not $AcceptanceEvidenceSha256) { $AcceptanceEvidenceSha256 = $EnvelopeSha256 }

    $claim = [ordered]@{
        schema = "antigravity-completion-claim-v1"
        producer_script_sha256 = (Get-FileHash -LiteralPath $claimProducerScript -Algorithm SHA256).Hash.ToLowerInvariant()
        claim_id = [guid]::NewGuid().ToString("N")
        objective_sha256 = ("a" * 64)
        claim_summary = "Verification-plane fixture completion request."
        actor = [ordered]@{
            role = $ActorRole
            id_sha256 = ("b" * 64)
        }
        requested_status = $RequestedStatus
        verification = [ordered]@{
            envelope_path = $EnvelopePath
            envelope_sha256 = $EnvelopeSha256
        }
        attempt_history = [ordered]@{
            ledger_path = $script:attemptLedgerPath
            ledger_sha256 = $script:attemptLedgerSha256
            report_path = $script:attemptReportPath
            report_sha256 = $script:attemptReportSha256
        }
        checker = [ordered]@{
            role = $CheckerRole
            independent = $Independent
        }
        acceptance_criteria = @(
            [ordered]@{
                id = $CriterionId
                status = "passed"
                evidence_sha256 = $AcceptanceEvidenceSha256
            }
        )
        remaining_uncertainty = @()
        created_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $claim | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

foreach ($schemaRelativePath in @(
    "src\schemas\verification-envelope.schema.json",
    "src\schemas\completion-claim.schema.json"
)) {
    $schemaPath = Join-Path $ProjectRoot $schemaRelativePath
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    Assert-True -Condition ([bool]$schema.'$schema') -Message "Schema declaration missing: $schemaRelativePath"
    Assert-True -Condition ([bool]$schema.required) -Message "Required fields missing: $schemaRelativePath"
}

foreach ($scriptPath in @($detectScript, $envelopeScript, $completionScript)) {
    $parseErrors = $null
    [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content -LiteralPath $scriptPath -Raw),
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) {
        throw ("PowerShell parse failure in {0}: {1}" -f $scriptPath, $parseErrors[0].Message)
    }
}

$tmpRoot = Join-Path $env:TEMP ("antigravity-verification-plane-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$canonicalTmpRoot = (Get-Item -LiteralPath $tmpRoot -Force).FullName

try {
    $package = [ordered]@{
        name = "verification-fixture"
        scripts = [ordered]@{
            test = "node fixture-test.js"
            typecheck = "node fixture-typecheck.js"
        }
    }
    $package | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tmpRoot "package.json") -Encoding UTF8
    Write-Fixture -Path (Join-Path $tmpRoot "src\harness-evals\test-demo.ps1") -Value "Write-Output 'fixture'"

    $surfaceRaw = & $detectScript -ProjectRoot $tmpRoot
    $surface = $surfaceRaw | ConvertFrom-Json
    Assert-True -Condition ($surface.schema -eq "antigravity-test-surface-v1") -Message "Test-surface schema mismatch."
    Assert-True -Condition ($surface.status -eq "detected") -Message "Expected a detected test surface."
    Assert-True -Condition (@($surface.candidates).Count -ge 2) -Message "Expected Node and PowerShell test candidates."
    Assert-True -Condition (-not ($surfaceRaw -match [regex]::Escape($tmpRoot))) -Message "Test-surface output leaked an absolute project path."

    Write-Fixture -Path (Join-Path $tmpRoot "source.txt") -Value "source-baseline"
    $fixtureTestCode = @'
$result = [ordered]@{
    schema = "antigravity-test-result-v1"
    cases = @([ordered]@{ id = "fixture-tests"; status = "passed" })
}
New-Item -ItemType Directory -Force -Path "artifacts\test-results" | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "artifacts\test-results\fixture.json" -Encoding UTF8
Write-Output "tests_collected=1"
'@
    Write-Fixture -Path (Join-Path $tmpRoot "tests\fixture.tests.ps1") -Value $fixtureTestCode
    Write-Fixture -Path (Join-Path $tmpRoot "protected.txt") -Value "protected-baseline"

    $passingCommand = "& '.\tests\fixture.tests.ps1'"
    $passParams = @{
        ProjectRoot = $tmpRoot
        Name = "passing fixture"
        Command = $passingCommand
        CommandLabel = "fixture verification"
        SourcePaths = @("source.txt")
        TestPaths = @("tests\fixture.tests.ps1")
        ProtectedPaths = @("protected.txt")
        RequireSourcePaths = $true
        RequireTestPaths = $true
        RequireProtectedPaths = $true
        RequireTestsCollected = $true
        RequireStructuredTestResult = $true
        TestResultPath = "artifacts\test-results\fixture.json"
        AcceptanceCriteria = @("fixture-tests")
        TimeoutSeconds = 10
    }
    $passRaw = & $envelopeScript @passParams
    $pass = $passRaw | ConvertFrom-Json
    Assert-True -Condition ($pass.status -eq "success") -Message "Passing envelope did not return success."
    Assert-True -Condition (Test-Path -LiteralPath $pass.manifest -PathType Leaf) -Message "Passing envelope manifest is missing."

    $manifestRaw = Get-Content -LiteralPath $pass.manifest -Raw
    $manifest = $manifestRaw | ConvertFrom-Json
    Assert-True -Condition ($manifest.schema -eq "antigravity-verification-envelope-v2") -Message "Verification envelope schema mismatch."
    Assert-True -Condition ($manifest.status -eq "passed") -Message "Passing envelope was not marked passed."
    Assert-True -Condition ($manifest.command.exit_code -eq 0) -Message "Passing envelope did not preserve exit code 0."
    Assert-True -Condition (-not $manifest.command.timed_out) -Message "Passing envelope was incorrectly timed out."
    Assert-True -Condition ($manifest.tests.collected_count -eq 1) -Message "Observed structured test count was not recorded."
    Assert-True -Condition ($manifest.tests.result_schema -eq "antigravity-test-result-v1") -Message "Structured test result schema missing."
    Assert-True -Condition (@($manifest.tests.passed_case_ids) -contains "fixture-tests") -Message "Passed case ID missing."
    Assert-True -Condition (-not $manifest.inputs.stale) -Message "Unchanged verification inputs were marked stale."
    Assert-True -Condition ($manifest.workspace.before_sha256 -eq $manifest.workspace.after_sha256) -Message "Unchanged workspace fingerprints differ."
    Assert-True -Condition ([bool]$manifest.inputs.before.source_sha256) -Message "Source before hash missing."
    Assert-True -Condition ([bool]$manifest.inputs.after.tests_sha256) -Message "Test after hash missing."
    Assert-True -Condition ([bool]$manifest.protected.before_sha256) -Message "Protected before hash missing."
    Assert-True -Condition ([bool]$manifest.protected.after_sha256) -Message "Protected after hash missing."
    Assert-True -Condition ([bool]$manifest.command.output_sha256) -Message "Output hash missing."
    Assert-True -Condition (-not ($manifestRaw -match "private-output-marker")) -Message "Envelope stored raw command output."
    Assert-True -Condition (-not ($manifestRaw -match [regex]::Escape($passingCommand))) -Message "Envelope stored the raw verification command."
    Assert-True -Condition (-not ($manifestRaw -match [regex]::Escape($tmpRoot))) -Message "Envelope leaked an absolute project path."
    Assert-True -Condition (Test-Path -LiteralPath $pass.manifest_hash_file -PathType Leaf) -Message "Detached envelope hash is missing."

    $ownedPassTemp = Join-Path ([IO.Path]::GetTempPath()) ("antigravity-verification-envelope-" + $pass.attempt_id)
    Assert-True -Condition (-not (Test-Path -LiteralPath $ownedPassTemp)) -Message "Passing envelope left its temporary directory behind."

    Assert-ExpectedFailure -Message "Envelope accepted an uncovered acceptance criterion." -Action {
        $uncoveredParams = $passParams.Clone()
        $uncoveredParams.Name = "uncovered structured criterion"
        $uncoveredParams.AcceptanceCriteria = @("links-valid")
        & $envelopeScript @uncoveredParams
    }
    $uncoveredStructuredArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "uncovered-structured-criterion"
    Assert-True -Condition (@($uncoveredStructuredArtifact.value.failures) -contains "acceptance-criterion-not-passed") -Message "Uncovered structured criterion failure code missing."

    Assert-ExpectedFailure -Message "An unbound command fabricated test collection evidence." -Action {
        $unboundParams = $passParams.Clone()
        $unboundParams.Name = "unbound test command"
        $unboundParams.Command = "Write-Output '.\tests\fixture.tests.ps1'; Write-Output 'tests_collected=99'"
        & $envelopeScript @unboundParams
    }
    $unboundArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "unbound-test-command"
    Assert-True -Condition (@($unboundArtifact.value.failures) -contains "test-command-not-bound") -Message "Unbound test command failure code is missing."
    Assert-True -Condition ($unboundArtifact.value.command.execution -eq "skipped-preflight") -Message "Unbound test command was executed."

    Assert-ExpectedFailure -Message "A success-shaped payload overrode a nonzero exit code." -Action {
        $failureParams = $passParams.Clone()
        $failureParams.Name = "success shaped failure"
        $failureParams.Command = "Write-Output '{""status"":""success""}'; exit 7"
        $failureParams.Remove("RequireTestsCollected")
        & $envelopeScript @failureParams
    }
    $exitFailureArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "success-shaped-failure"
    Assert-True -Condition ($exitFailureArtifact.value.status -eq "failed") -Message "Nonzero exit envelope was not failed."
    Assert-True -Condition ($exitFailureArtifact.value.command.exit_code -eq 7) -Message "Real child-process exit code was not preserved."
    Assert-True -Condition (@($exitFailureArtifact.value.failures) -contains "process-exit") -Message "Nonzero exit failure code is missing."
    Assert-True -Condition (-not ($exitFailureArtifact.raw -match '""status"":""success""')) -Message "Failure envelope stored success-shaped raw output."

    $sentinel = Join-Path $tmpRoot "preflight-command-ran.txt"
    Assert-ExpectedFailure -Message "Missing required verification input did not fail closed." -Action {
        $missingParams = @{
            ProjectRoot = $tmpRoot
            Name = "missing required source"
            Command = "Set-Content -LiteralPath '.\preflight-command-ran.txt' -Value 'ran'"
            SourcePaths = @("missing-source.txt")
            TestPaths = @("tests\fixture.tests.ps1")
            ProtectedPaths = @("protected.txt")
            RequireSourcePaths = $true
            RequireTestPaths = $true
            RequireProtectedPaths = $true
        }
        & $envelopeScript @missingParams
    }
    Assert-True -Condition (-not (Test-Path -LiteralPath $sentinel)) -Message "Preflight failure still executed the verification command."
    $missingArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "missing-required-source"
    Assert-True -Condition (@($missingArtifact.value.failures) -contains "source-path-missing") -Message "Missing source path was not recorded."
    Assert-True -Condition ($missingArtifact.value.command.execution -eq "skipped-preflight") -Message "Missing input did not skip execution."

    Assert-ExpectedFailure -Message "Zero tests collected was accepted as verification." -Action {
        $zeroTestCode = @'
$result = [ordered]@{ schema = "antigravity-test-result-v1"; cases = @() }
New-Item -ItemType Directory -Force -Path "artifacts\test-results" | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "artifacts\test-results\zero.json" -Encoding UTF8
Write-Output "tests_collected=0"
'@
        Write-Fixture -Path (Join-Path $tmpRoot "tests\zero.tests.ps1") -Value $zeroTestCode
        $zeroParams = $passParams.Clone()
        $zeroParams.Name = "zero tests"
        $zeroParams.Command = "& '.\tests\zero.tests.ps1'"
        $zeroParams.TestPaths = @("tests\zero.tests.ps1")
        $zeroParams.TestResultPath = "artifacts\test-results\zero.json"
        $zeroParams.AcceptanceCriteria = @()
        & $envelopeScript @zeroParams
    }
    $zeroArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "zero-tests"
    Assert-True -Condition (@($zeroArtifact.value.failures) -contains "zero-tests-collected") -Message "Zero-test failure code is missing."
    Assert-True -Condition ($zeroArtifact.value.tests.collected_count -eq 0) -Message "Zero observed tests were not recorded."

    Write-Fixture -Path (Join-Path $tmpRoot "stale-source.txt") -Value "before"
    Assert-ExpectedFailure -Message "Source mutation during verification did not invalidate the envelope." -Action {
        $staleParams = @{
            ProjectRoot = $tmpRoot
            Name = "stale source"
            Command = "Set-Content -LiteralPath '.\stale-source.txt' -Value 'after'; & '.\tests\fixture.tests.ps1'"
            SourcePaths = @("stale-source.txt")
            TestPaths = @("tests\fixture.tests.ps1")
            ProtectedPaths = @("protected.txt")
            RequireSourcePaths = $true
            RequireTestPaths = $true
            RequireProtectedPaths = $true
            RequireTestsCollected = $true
            TimeoutSeconds = 10
        }
        & $envelopeScript @staleParams
    }
    $staleArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "stale-source"
    Assert-True -Condition ($staleArtifact.value.inputs.stale) -Message "Stale input flag is false."
    Assert-True -Condition (@($staleArtifact.value.inputs.stale_paths) -contains "stale-source.txt") -Message "Mutated source path was not identified."

    Write-Fixture -Path (Join-Path $tmpRoot "protected-timeout.txt") -Value "protected"
    $lateEvidence = Join-Path $tmpRoot "late-timeout-side-effect.txt"
    $escapedLateEvidence = $lateEvidence.Replace("'", "''")
    $childCommand = "Start-Sleep -Seconds 2; Set-Content -LiteralPath '$escapedLateEvidence' -Value 'late'"
    $encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $timeoutCommand = "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-EncodedCommand','$encodedChild') -WindowStyle Hidden | Out-Null; Start-Sleep -Seconds 8; & '.\tests\fixture.tests.ps1'"
    Assert-ExpectedFailure -Message "Finite verification timeout was not enforced." -Action {
        $timeoutParams = @{
            ProjectRoot = $tmpRoot
            Name = "timeout process tree"
            Command = $timeoutCommand
            SourcePaths = @("source.txt")
            TestPaths = @("tests\fixture.tests.ps1")
            ProtectedPaths = @("protected-timeout.txt")
            RequireSourcePaths = $true
            RequireTestPaths = $true
            RequireProtectedPaths = $true
            RequireTestsCollected = $true
            TimeoutSeconds = 1
        }
        & $envelopeScript @timeoutParams
    }
    $timeoutArtifact = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\verification-envelopes" -FileName "envelope.json" -DirectoryContains "timeout-process-tree"
    Assert-True -Condition ($timeoutArtifact.value.command.timed_out) -Message "Timeout was not recorded."
    Assert-True -Condition ($timeoutArtifact.value.command.exit_code -eq 124) -Message "Timeout exit code 124 was not recorded."
    Start-Sleep -Seconds 3
    Assert-True -Condition (-not (Test-Path -LiteralPath $lateEvidence)) -Message "Timed-out descendant process produced a late side effect."
    $ownedTimeoutTemp = Join-Path ([IO.Path]::GetTempPath()) ("antigravity-verification-envelope-" + $timeoutArtifact.value.attempt_id)
    Assert-True -Condition (-not (Test-Path -LiteralPath $ownedTimeoutTemp)) -Message "Failed envelope left its temporary directory behind."

    $completionPassParams = $passParams.Clone()
    $claimContractRaw = & (Join-Path $ProjectRoot "src\scripts\new-task-contract.ps1") -ProjectRoot $tmpRoot -StateRoot (Join-Path $tmpRoot 'harness-state') -Objective "Verification-plane fixture completion request" -AllowedPaths @("source.txt") -ContractId "verification-canary"
    $claimContract = $claimContractRaw | ConvertFrom-Json
    $completionPassParams.TaskId='verification-canary'
    $completionPassParams.TaskAttemptId='attempt-2'
    $completionPassParams.ContractPath=$claimContract.path
    $completionPassParams.Name = "completion current workspace"
    $completionPassRaw = & $envelopeScript @completionPassParams
    $completionPass = $completionPassRaw | ConvertFrom-Json
    Assert-True -Condition ($completionPass.status -eq "success") -Message "Fresh completion envelope did not pass."

    $attemptStateRoot = Join-Path $tmpRoot "harness-state"
    Write-Fixture -Path (Join-Path $tmpRoot "artifacts\attempt-evidence\attempt-1.json") -Value "{}"
    Write-Fixture -Path (Join-Path $tmpRoot "artifacts\attempt-evidence\attempt-2.json") -Value "{}"
    $attemptOne = (& $newAttemptScript -StateRoot $attemptStateRoot -ProjectRoot $tmpRoot -InputPaths @("source.txt") -TaskId "verification-canary" -OperationId "completion" -AttemptId "attempt-1") | ConvertFrom-Json
    $null = & $updateAttemptScript -LedgerPath $attemptOne.path -AttemptId "attempt-1" -ExpectedVersion 1 -Status "failed" -ExitCode 1 -FailureClass "assumption-error" -RecoveryAction "Correct the completion request" -EvidenceArtifact "artifacts/attempt-evidence/attempt-1.json"
    $attemptTwo = (& $newAttemptScript -StateRoot $attemptStateRoot -ProjectRoot $tmpRoot -InputPaths @("source.txt") -TaskId "verification-canary" -OperationId "completion" -AttemptId "attempt-2" -ExpectedVersion 2) | ConvertFrom-Json
    $null = & $updateAttemptScript -LedgerPath $attemptOne.path -AttemptId "attempt-2" -ExpectedVersion 3 -Status "passed" -ExitCode 0 -RecoveryAction "Submitted checking instead of verified" -EvidenceArtifact "artifacts/attempt-evidence/attempt-2.json"
    $attemptReport = (& $renderAttemptReportScript -LedgerPath $attemptOne.path) | ConvertFrom-Json
    $script:attemptLedgerPath = $attemptOne.path
    $script:attemptLedgerSha256 = (Get-FileHash -LiteralPath $attemptOne.path -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:attemptReportPath = $attemptReport.report
    $script:attemptReportSha256 = $attemptReport.report_sha256

    $envelopeRelativePath = $completionPass.manifest.Substring($canonicalTmpRoot.Length).TrimStart('\', '/')
    $claimsRoot = Join-Path $tmpRoot "artifacts\completion-claims"
    $makerClaim = Join-Path $claimsRoot "maker-verified.json"
    Write-CompletionClaim -Path $makerClaim -ActorRole "maker" -RequestedStatus "verified" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $false
    Assert-ExpectedFailure -Message "Maker directly issued verified." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $makerClaim
    }
    $makerDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition ($makerDecision.value.status -eq "unverified") -Message "Maker self-verification was not rejected."
    Assert-True -Condition (@($makerDecision.value.failures) -contains "maker-self-verification") -Message "Maker self-verification failure code missing."

    $makerPlannedClaim = Join-Path $claimsRoot "maker-planned.json"
    Write-CompletionClaim -Path $makerPlannedClaim -ActorRole "maker" -RequestedStatus "planned" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $true -CheckerRole "reviewer"
    Assert-ExpectedFailure -Message "Maker completion request bypassed checker authority." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $makerPlannedClaim
    }
    $makerPlannedDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($makerPlannedDecision.value.failures) -contains "completion-requester-not-checker") -Message "Maker completion requester failure code missing."

    $mismatchedEvidenceClaim = Join-Path $claimsRoot "reviewer-mismatched-evidence.json"
    Write-CompletionClaim -Path $mismatchedEvidenceClaim -ActorRole "reviewer" -RequestedStatus "checking" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $true -AcceptanceEvidenceSha256 ("f" * 64)
    Assert-ExpectedFailure -Message "Unrelated acceptance evidence hash was accepted." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $mismatchedEvidenceClaim
    }
    $mismatchedDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($mismatchedDecision.value.failures) -contains "acceptance-evidence-mismatch") -Message "Acceptance evidence mismatch code missing."

    $uncoveredCriterionClaim = Join-Path $claimsRoot "reviewer-uncovered-criterion.json"
    Write-CompletionClaim -Path $uncoveredCriterionClaim -ActorRole "reviewer" -RequestedStatus "checking" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $true -CriterionId "arbitrary-unverified-business-criterion"
    Assert-ExpectedFailure -Message "Claim introduced an acceptance criterion not covered by the envelope." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $uncoveredCriterionClaim
    }
    $uncoveredDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($uncoveredDecision.value.failures) -contains "acceptance-criterion-not-covered") -Message "Uncovered acceptance criterion failure code missing."

    $tamperedReportPath = Join-Path $claimsRoot "tampered-attempt-report.json"
    $tamperedReport = Get-Content -LiteralPath $script:attemptReportPath -Raw | ConvertFrom-Json
    $tamperedReport.attempts = @($tamperedReport.attempts | Select-Object -Last 1)
    $tamperedReport.attempt_count = 1
    $tamperedReport.failed_count = 0
    $tamperedReport.status = "passed"
    $tamperedReport.producer_script_sha256 = ("f" * 64)
    $tamperedReport | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tamperedReportPath -Encoding UTF8
    $originalReportPath = $script:attemptReportPath
    $originalReportSha = $script:attemptReportSha256
    $script:attemptReportPath = $tamperedReportPath
    $script:attemptReportSha256 = (Get-FileHash -LiteralPath $tamperedReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tamperedClaim = Join-Path $claimsRoot "reviewer-tampered-attempt-report.json"
    Write-CompletionClaim -Path $tamperedClaim -ActorRole "reviewer" -RequestedStatus "checking" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $true
    Assert-ExpectedFailure -Message "Completion gate accepted an attempt report that omitted a failed attempt." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $tamperedClaim
    }
    $tamperedDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($tamperedDecision.value.failures) -contains "attempt-report-mismatch") -Message "Tampered attempt report failure code missing."
    Assert-True -Condition (@($tamperedDecision.value.failures) -contains "attempt-provenance-invalid") -Message "Attempt provenance failure code missing."
    $script:attemptReportPath = $originalReportPath
    $script:attemptReportSha256 = $originalReportSha

    Assert-True -Condition ($claimContract.status -eq "success") -Message "Claim fixture contract creation failed."

    $incompleteLedgerPath = Join-Path $claimsRoot "incomplete-observation-ledger.json"
    $incompleteReportPath = Join-Path $claimsRoot "incomplete-observation-report.json"
    $incompleteLedger = Get-Content -LiteralPath $script:attemptLedgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $incompleteReport = Get-Content -LiteralPath $script:attemptReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $incompleteLedger.attempts[0].workspace_after_sha256 = $null
    $incompleteReport.attempts[0].workspace_after_sha256 = $null
    $incompleteLedger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $incompleteLedgerPath -Encoding UTF8
    $incompleteReport | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $incompleteReportPath -Encoding UTF8
    $incompleteClaimRaw = & $claimProducerScript -ProjectRoot $tmpRoot -ContractPath $claimContract.path -EnvelopePath $completionPass.manifest -LedgerPath $incompleteLedgerPath -ReportPath $incompleteReportPath -TestResultPath "artifacts\test-results\fixture.json" -AcceptanceCriterionIds @("fixture-tests") -ClaimSummary "Reject incomplete attempt observation." -ActorRole "reviewer" -ActorId "verification-plane-reviewer" -RequestedStatus "checking" -CheckerRole "reviewer" -CheckerIndependent
    $incompleteClaim = $incompleteClaimRaw | ConvertFrom-Json
    Assert-True -Condition ($incompleteClaim.status -eq "success") -Message "Incomplete-observation fixture claim generation failed."
    Assert-ExpectedFailure -Message "Completion gate accepted a terminal attempt without workspace-after evidence." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $incompleteClaim.claim
    }
    $incompleteDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($incompleteDecision.value.failures) -contains "attempt-observation-incomplete") -Message "Incomplete attempt observation failure code missing."

    $canonicalClaimRaw = & $claimProducerScript -ProjectRoot $tmpRoot -ContractPath $claimContract.path -EnvelopePath $completionPass.manifest -LedgerPath $script:attemptLedgerPath -ReportPath $script:attemptReportPath -TestResultPath "artifacts\test-results\fixture.json" -AcceptanceCriterionIds @("fixture-tests") -ClaimSummary "Verification-plane fixture completion request." -ActorRole "reviewer" -ActorId "verification-plane-reviewer" -RequestedStatus "checking" -CheckerRole "reviewer" -CheckerIndependent
    $canonicalClaim = $canonicalClaimRaw | ConvertFrom-Json
    Assert-True -Condition ($canonicalClaim.status -eq "success") -Message "Canonical completion claim generation failed: $($canonicalClaim.error)"
    $reviewerClaim = $canonicalClaim.claim
    $canonicalClaimValue = Get-Content -LiteralPath $reviewerClaim -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($canonicalClaimValue.producer_script_sha256 -eq (Get-FileHash -LiteralPath $claimProducerScript -Algorithm SHA256).Hash.ToLowerInvariant()) -Message "Canonical completion claim producer hash is missing or stale."
    $completionRaw = & $completionScript -ProjectRoot $tmpRoot -ClaimPath $reviewerClaim
    $completion = $completionRaw | ConvertFrom-Json
    Assert-True -Condition ($completion.status -eq "success") -Message "Valid independent completion request was rejected."
    Assert-True -Condition ($completion.decision_status -eq "checking") -Message "Unattested checker identity must remain checking."
    $checkingDecisionRaw = Get-Content -LiteralPath $completion.decision -Raw
    $checkingDecision = $checkingDecisionRaw | ConvertFrom-Json
    Assert-True -Condition ($checkingDecision.status -eq "checking") -Message "Evidence-valid unattested decision must remain checking."
    Assert-True -Condition ($checkingDecision.authority_status -eq "unverified") -Message "Checker authority must be explicitly unverified."
    Assert-True -Condition (-not ($checkingDecisionRaw -match [regex]::Escape($tmpRoot))) -Message "Completion decision leaked an absolute project path."
    Assert-True -Condition (-not ($checkingDecisionRaw -match [regex]::Escape($passingCommand))) -Message "Completion decision stored the raw verification command."

    $attemptEvidencePath = Join-Path $tmpRoot "artifacts\attempt-evidence\attempt-2.json"
    $attemptEvidenceBytes = [IO.File]::ReadAllBytes($attemptEvidencePath)
    [IO.File]::WriteAllText($attemptEvidencePath, "tampered", (New-Object Text.UTF8Encoding($false)))
    $tamperedAttemptEvidenceClaim = Join-Path $claimsRoot "reviewer-tampered-attempt-evidence.json"
    Write-CompletionClaim -Path $tamperedAttemptEvidenceClaim -ActorRole "reviewer" -RequestedStatus "checking" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $true
    Assert-ExpectedFailure -Message "Changed attempt evidence artifact was accepted." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $tamperedAttemptEvidenceClaim
    }
    $tamperedAttemptDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($tamperedAttemptDecision.value.failures) -contains "attempt-evidence-invalid") -Message "Attempt evidence integrity failure code missing."
    [IO.File]::WriteAllBytes($attemptEvidencePath, $attemptEvidenceBytes)

    Write-Fixture -Path (Join-Path $tmpRoot "source.txt") -Value "changed-after-verification"
    $staleClaim = Join-Path $claimsRoot "reviewer-stale.json"
    Write-CompletionClaim -Path $staleClaim -ActorRole "reviewer" -RequestedStatus "checking" -EnvelopePath $envelopeRelativePath -EnvelopeSha256 $completionPass.manifest_sha256 -Independent $true
    Assert-ExpectedFailure -Message "Workspace change after verification did not invalidate completion." -Action {
        & $completionScript -ProjectRoot $tmpRoot -ClaimPath $staleClaim
    }
    $staleDecision = Get-LatestJsonArtifact -Root $tmpRoot -RelativeArtifactRoot "artifacts\completion-gates" -FileName "decision.json"
    Assert-True -Condition (@($staleDecision.value.failures) -contains "workspace-changed") -Message "Workspace-change failure code missing."
    Assert-True -Condition (@($staleDecision.value.failures) -contains "source-state-changed") -Message "Changed source input was not identified."

    [ordered]@{
        status = "success"
        summary = "Antigravity verification plane checks passed."
        cases = @(
            "schema-and-parser",
            "test-surface-detection",
            "passing-envelope",
            "test-command-binding",
            "structured-test-case-binding",
            "success-shaped-nonzero-exit",
            "required-path-fail-closed",
            "zero-tests-collected",
            "stale-input",
            "timeout-process-tree",
            "temp-cleanup",
            "maker-self-verification",
            "maker-requester-rejected",
            "acceptance-evidence-binding",
            "acceptance-criterion-coverage",
            "attempt-ledger-completeness",
            "unattested-checker-remains-checking",
            "attempt-evidence-integrity",
            "post-verification-workspace-change"
        )
    } | ConvertTo-Json -Depth 6 -Compress
} finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}
