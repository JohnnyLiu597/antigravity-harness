param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$ClaimPath,
    [switch]$ReadOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
Set-StrictMode -Off

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-Sha256 {
    param([AllowEmptyString()][string]$Value)

    return ([string]$Value -match '^[a-f0-9]{64}$')
}

function Add-FailureCode {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List,
        [Parameter(Mandatory = $true)][string]$Code
    )

    if (-not $List.Contains($Code)) {
        $List.Add($Code) | Out-Null
    }
}

function Resolve-InsideProject {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = Get-AgPath $Root
    $candidate = Get-AgPath $Path $normalizedRoot
    $prefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    if ($candidate.Substring([IO.Path]::GetPathRoot($candidate).Length).Contains(':')) { throw 'Alternate data streams are not evidence files.' }
    if (-not $candidate.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase) -and
        -not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the project boundary."
    }
    $cursor=$candidate
    while($cursor -and $cursor.Length -ge $normalizedRoot.Length){
        if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType -eq 'HardLink')){throw 'Linked evidence paths are not supported.'}}
        $next=Split-Path -Parent $cursor;if($next -eq $cursor){break};$cursor=$next
    }
    return $candidate
}

function Resolve-EvidencePath {
    param([string]$Root, [string]$Path)
    try { return Resolve-InsideProject -Root $Root -Path $Path } catch {}
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "Evidence path is outside the project boundary." }
    $candidate = [IO.Path]::GetFullPath($Path)
    $cursor = if (Test-Path -LiteralPath $candidate -PathType Container) { $candidate } else { Split-Path -Parent $candidate }
    while ($cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor ".gemini-private") -PathType Leaf) { return $candidate }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    throw "External evidence path is not under a marked private state root."
}

function Get-RelativeProjectPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $normalizedPath = [IO.Path]::GetFullPath($Path)
    if ($normalizedPath.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }
    $prefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $normalizedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return "<external>"
    }
    return $normalizedPath.Substring($prefix.Length).Replace('\', '/')
}

function Get-PathDigest {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    try {
        $fullPath = Resolve-InsideProject -Root $Root -Path $RelativePath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            return [ordered]@{
                path = $RelativePath.Replace('\', '/')
                type = "missing"
                sha256 = ""
                files = 0
                bytes = 0
            }
        }
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            return [ordered]@{
                path = $RelativePath.Replace('\', '/')
                type = "file"
                sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                files = 1
                bytes = [long]$item.Length
            }
        }
        if (Test-Path -LiteralPath $fullPath -PathType Container) {
            $prefix = $fullPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            $lines = New-Object System.Collections.Generic.List[string]
            $totalBytes = [long]0
            foreach ($file in @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force -File -ErrorAction Stop | Sort-Object FullName)) {
                $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $lines.Add("$relative|$hash|$([long]$file.Length)") | Out-Null
                $totalBytes += [long]$file.Length
            }
            return [ordered]@{
                path = $RelativePath.Replace('\', '/')
                type = "directory"
                sha256 = Get-Sha256Text -Text ($lines -join [Environment]::NewLine)
                files = $lines.Count
                bytes = $totalBytes
            }
        }
    } catch {
    }

    return [ordered]@{
        path = $RelativePath.Replace('\', '/')
        type = "error"
        sha256 = ""
        files = 0
        bytes = 0
    }
}

function Compare-RecordedDigests {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [object[]]$Recorded
    )

    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($record in @($Recorded)) {
        $current = Get-PathDigest -Root $Root -RelativePath ([string]$record.path)
        if ($current.type -ne [string]$record.type -or
            $current.sha256 -ne [string]$record.sha256 -or
            [long]$current.files -ne [long]$record.files -or
            [long]$current.bytes -ne [long]$record.bytes) {
            $changed.Add([string]$record.path) | Out-Null
        }
    }
    return @($changed.ToArray() | Sort-Object -Unique)
}

function Test-GitWorkspace {
    param([Parameter(Mandatory = $true)][string]$Root)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return $false
    }
    try {
        $global:LASTEXITCODE = 0
        $value = @(& $git.Source -C $Root rev-parse --is-inside-work-tree 2>$null)
        return ($LASTEXITCODE -eq 0 -and (($value -join "").Trim()) -eq "true")
    } catch {
        return $false
    }
}

function Get-WorkspaceFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ExpectedAlgorithm,
        [string[]]$ExcludedRoots
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $paths = @()
    $algorithm = $ExpectedAlgorithm

    if ($ExpectedAlgorithm -eq "git-content-v1") {
        if (-not (Test-GitWorkspace -Root $Root)) {
            return [pscustomobject]@{
                algorithm = "unavailable"
                sha256 = Get-Sha256Text -Text ""
                files = 0
            }
        }
        $git = Get-Command git -ErrorAction Stop
        try {
            $global:LASTEXITCODE = 0
            $listed = @(& $git.Source -C $Root ls-files --cached --others --exclude-standard 2>$null)
            if ($LASTEXITCODE -ne 0) {
                throw "git ls-files failed"
            }
            $paths = @($listed | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        } catch {
            return [pscustomobject]@{
                algorithm = "unavailable"
                sha256 = Get-Sha256Text -Text ""
                files = 0
            }
        }
    } elseif ($ExpectedAlgorithm -eq "filesystem-content-v1") {
        $rootPrefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $paths = @(
            Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $relative = $_.FullName.Substring($rootPrefix.Length).Replace('\', '/')
                    $firstSegment = @($relative -split '/')[0]
                    if ($firstSegment -notin @($ExcludedRoots)) {
                        $relative
                    }
                } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
    } else {
        return [pscustomobject]@{
            algorithm = "unavailable"
            sha256 = Get-Sha256Text -Text ""
            files = 0
        }
    }

    foreach ($relative in $paths) {
        $fullPath = Join-Path $Root $relative
        try {
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
                $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $lines.Add("$($relative.Replace('\', '/'))|$hash|$([long]$item.Length)") | Out-Null
            } else {
                $lines.Add("$($relative.Replace('\', '/'))|missing|0") | Out-Null
            }
        } catch {
            $lines.Add("$($relative.Replace('\', '/'))|error|0") | Out-Null
        }
    }

    return [pscustomobject]@{
        algorithm = $algorithm
        sha256 = Get-Sha256Text -Text ($lines -join [Environment]::NewLine)
        files = $lines.Count
    }
}

$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$failureCodes = New-Object System.Collections.Generic.List[string]
$startedAt = Get-Date
$decisionId = $startedAt.ToUniversalTime().ToString("yyyyMMdd-HHmmssfff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
$claim = $null
$claimFullPath = $null
$claimHash = Get-Sha256Text -Text ""
$envelope = $null
$envelopeFullPath = $null
$envelopeHash = Get-Sha256Text -Text ""
$currentWorkspace = $null
$sourceChanges = @()
$testChanges = @()
$protectedChanges = @()
$attemptLedger = $null
$attemptReport = $null
$attemptLedgerFullPath = $null
$attemptReportFullPath = $null

try {
    $claimFullPath = Resolve-InsideProject -Root $root -Path $ClaimPath
    if (-not (Test-Path -LiteralPath $claimFullPath -PathType Leaf)) {
        Add-FailureCode -List $failureCodes -Code "claim-missing"
    } else {
        $claimHash = (Get-FileHash -LiteralPath $claimFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        try {
            $claim = Get-Content -LiteralPath $claimFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Add-FailureCode -List $failureCodes -Code "claim-json-invalid"
        }
    }
} catch {
    Add-FailureCode -List $failureCodes -Code "claim-path-invalid"
}

if ($claim) {
    if ([string]$claim.schema -ne "antigravity-completion-claim-v1") {
        Add-FailureCode -List $failureCodes -Code "claim-schema-invalid"
    }
    $expectedClaimProducer = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "new-completion-claim.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$claim.producer_script_sha256 -ne $expectedClaimProducer) {
        Add-FailureCode -List $failureCodes -Code "claim-provenance-invalid"
    }
    if (-not (Test-Sha256 -Value ([string]$claim.objective_sha256))) {
        Add-FailureCode -List $failureCodes -Code "objective-hash-invalid"
    }

    $actorRole = [string]$claim.actor.role
    $requestedStatus = [string]$claim.requested_status
    if ($actorRole -eq "maker" -and $requestedStatus -in @("verified", "approved")) {
        Add-FailureCode -List $failureCodes -Code "maker-self-verification"
    } elseif ($requestedStatus -eq "verified" -and $actorRole -ne "completion-gate") {
        Add-FailureCode -List $failureCodes -Code "verified-self-issued"
    }

    if (-not [bool]$claim.checker.independent) {
        Add-FailureCode -List $failureCodes -Code "checker-not-independent"
    }
    if ([string]$claim.checker.role -notin @("test-runner", "reviewer", "human")) {
        Add-FailureCode -List $failureCodes -Code "checker-role-invalid"
    }
    if ($actorRole -notin @("test-runner", "reviewer", "human") -or
        $actorRole -ne [string]$claim.checker.role) {
        Add-FailureCode -List $failureCodes -Code "completion-requester-not-checker"
    }
    if ($requestedStatus -ne "checking") {
        Add-FailureCode -List $failureCodes -Code "completion-request-status-invalid"
    }

    $criteria = @($claim.acceptance_criteria)
    if ($criteria.Count -eq 0) {
        Add-FailureCode -List $failureCodes -Code "acceptance-criteria-empty"
    }
    foreach ($criterion in $criteria) {
        if ([string]$criterion.status -ne "passed") {
            Add-FailureCode -List $failureCodes -Code "acceptance-criterion-unverified"
        }
        if (-not (Test-Sha256 -Value ([string]$criterion.evidence_sha256))) {
            Add-FailureCode -List $failureCodes -Code "acceptance-evidence-invalid"
        }
        if ([string]$criterion.evidence_sha256 -ne [string]$claim.verification.envelope_sha256) {
            Add-FailureCode -List $failureCodes -Code "acceptance-evidence-mismatch"
        }
    }

    if (-not $claim.attempt_history) {
        Add-FailureCode -List $failureCodes -Code "attempt-history-missing"
    } else {
        try {
            $attemptLedgerFullPath = Resolve-EvidencePath -Root $root -Path ([string]$claim.attempt_history.ledger_path)
            $attemptReportFullPath = Resolve-EvidencePath -Root $root -Path ([string]$claim.attempt_history.report_path)
            if (-not (Test-Path -LiteralPath $attemptLedgerFullPath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $attemptReportFullPath -PathType Leaf)) {
                Add-FailureCode -List $failureCodes -Code "attempt-history-missing"
            } else {
                $actualLedgerHash = (Get-FileHash -LiteralPath $attemptLedgerFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $actualReportHash = (Get-FileHash -LiteralPath $attemptReportFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualLedgerHash -ne [string]$claim.attempt_history.ledger_sha256 -or
                    $actualReportHash -ne [string]$claim.attempt_history.report_sha256) {
                    Add-FailureCode -List $failureCodes -Code "attempt-history-hash-mismatch"
                }
                $attemptLedger = Get-Content -LiteralPath $attemptLedgerFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $attemptReport = Get-Content -LiteralPath $attemptReportFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
        } catch {
            Add-FailureCode -List $failureCodes -Code "attempt-history-invalid"
        }
    }

    try {
        $envelopeFullPath = Resolve-InsideProject -Root $root -Path ([string]$claim.verification.envelope_path)
        if (-not (Test-Path -LiteralPath $envelopeFullPath -PathType Leaf)) {
            Add-FailureCode -List $failureCodes -Code "envelope-missing"
        } else {
            $envelopeHash = (Get-FileHash -LiteralPath $envelopeFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if (-not (Test-Sha256 -Value ([string]$claim.verification.envelope_sha256)) -or
                $envelopeHash -ne [string]$claim.verification.envelope_sha256) {
                Add-FailureCode -List $failureCodes -Code "envelope-hash-mismatch"
            }

            $detachedHashPath = Join-Path (Split-Path -Parent $envelopeFullPath) "envelope.sha256"
            if (-not (Test-Path -LiteralPath $detachedHashPath -PathType Leaf)) {
                Add-FailureCode -List $failureCodes -Code "envelope-detached-hash-missing"
            } else {
                $detachedHash = (Get-Content -LiteralPath $detachedHashPath -Raw).Trim().ToLowerInvariant()
                if ($detachedHash -ne $envelopeHash) {
                    Add-FailureCode -List $failureCodes -Code "envelope-detached-hash-mismatch"
                }
            }

            try {
                $envelope = Get-Content -LiteralPath $envelopeFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                Add-FailureCode -List $failureCodes -Code "envelope-json-invalid"
            }
        }
    } catch {
        Add-FailureCode -List $failureCodes -Code "envelope-path-invalid"
    }
}

if ($envelope) {
    if($envelope.script_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'invoke-verification-envelope.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()){Add-FailureCode $failureCodes 'envelope-producer-stale'}
    if($envelope.project.root_sha256 -ne (Get-Sha256Text -Text $root.ToLowerInvariant())){Add-FailureCode $failureCodes 'envelope-project-mismatch'}
    if ([string]$envelope.schema -ne "antigravity-verification-envelope-v2") {
        Add-FailureCode -List $failureCodes -Code "envelope-schema-invalid"
    }
    if ([string]$envelope.status -ne "passed" -or @($envelope.failures).Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "envelope-not-passed"
    }
    if ([string]$envelope.command.execution -ne "ran" -or
        $envelope.command.exit_code -ne 0 -or
        [bool]$envelope.command.timed_out -or
        [bool]$envelope.command.launch_failed) {
        Add-FailureCode -List $failureCodes -Code "command-not-passed"
    }
    if (-not [bool]$envelope.requirements.satisfied) {
        Add-FailureCode -List $failureCodes -Code "requirements-unsatisfied"
    }
    if ([bool]$envelope.inputs.stale) {
        Add-FailureCode -List $failureCodes -Code "envelope-input-stale"
    }
    if ([bool]$envelope.protected.changed) {
        Add-FailureCode -List $failureCodes -Code "envelope-protected-change"
    }
    if ([bool]$envelope.workspace.changed) {
        Add-FailureCode -List $failureCodes -Code "envelope-workspace-changed"
    }
    if ([bool]$envelope.tests.require_collection -and
        (-not [bool]$envelope.tests.collection_observed -or [int]$envelope.tests.collected_count -le 0)) {
        Add-FailureCode -List $failureCodes -Code "tests-not-collected"
    }
    $coveredCriteria = @($envelope.acceptance_criteria)
    foreach ($criterion in @($claim.acceptance_criteria)) {
        if ([string]$criterion.id -notin $coveredCriteria) {
            Add-FailureCode -List $failureCodes -Code "acceptance-criterion-not-covered"
        }
    }

    $sourceChanges = @(Compare-RecordedDigests -Root $root -Recorded @($envelope.inputs.after.source))
    $testChanges = @(Compare-RecordedDigests -Root $root -Recorded @($envelope.inputs.after.tests))
    $protectedChanges = @(Compare-RecordedDigests -Root $root -Recorded @($envelope.protected.after))
    if ($sourceChanges.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "source-state-changed"
    }
    if ($testChanges.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "test-state-changed"
    }
    if ($protectedChanges.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "protected-state-changed"
    }

    $currentWorkspace = Get-WorkspaceFingerprint -Root $root -ExpectedAlgorithm ([string]$envelope.workspace.algorithm) -ExcludedRoots @($envelope.workspace.excluded_roots)
    if ($currentWorkspace.algorithm -eq "unavailable") {
        Add-FailureCode -List $failureCodes -Code "workspace-fingerprint-unavailable"
    } elseif ($currentWorkspace.sha256 -ne [string]$envelope.workspace.after_sha256) {
        Add-FailureCode -List $failureCodes -Code "workspace-changed"
    }
}

if ($attemptLedger -and $attemptReport) {
    $expectedAttemptProducer = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "new-attempt-record.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedUpdateProducer = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "update-attempt-record.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedReportProducer = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "render-completion-report.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($attemptLedger.producer_script_sha256 -ne $expectedAttemptProducer -or
        $attemptLedger.last_update_script_sha256 -ne $expectedUpdateProducer -or
        $attemptReport.producer_script_sha256 -ne $expectedReportProducer) {
        Add-FailureCode -List $failureCodes -Code "attempt-provenance-invalid"
    }
    $ledgerAttempts = @($attemptLedger.attempts | Sort-Object sequence)
    $reportAttempts = @($attemptReport.attempts | Sort-Object sequence)
    $ledgerFailures = @($ledgerAttempts | Where-Object { $_.status -in @("failed", "rejected", "blocked") })
    $expectedStatus = if ($ledgerAttempts.Count -eq 0 -or @($ledgerAttempts | Where-Object { $_.status -eq "running" }).Count -gt 0) {
        "incomplete"
    } elseif ($ledgerAttempts[-1].status -eq "passed" -and $ledgerFailures.Count -gt 0) {
        "passed_after_retry"
    } elseif ($ledgerAttempts[-1].status -eq "passed") {
        "passed"
    } else {
        [string]$ledgerAttempts[-1].status
    }
    foreach ($attempt in $ledgerAttempts) {
        if ($attemptLedger.project_root -and $attempt.status -ne "running") {
            $hasChangedPaths = $attempt.PSObject.Properties.Name -contains "changed_paths"
            $changedPathCount = if ($hasChangedPaths) { @($attempt.changed_paths).Count } else { -1 }
            if (-not (Test-Sha256 -Value ([string]$attempt.workspace_before_sha256)) -or
                -not (Test-Sha256 -Value ([string]$attempt.workspace_after_sha256)) -or
                -not $hasChangedPaths -or
                (([string]$attempt.workspace_before_sha256 -ne [string]$attempt.workspace_after_sha256) -and $changedPathCount -eq 0) -or
                ($changedPathCount -gt 0 -and -not [bool]$attempt.side_effects_observed)) {
                Add-FailureCode -List $failureCodes -Code "attempt-observation-incomplete"
            }
        }
        try {
            if (-not $attempt.evidence_artifact -or -not (Test-Sha256 -Value ([string]$attempt.evidence_sha256))) { throw "missing" }
            $attemptEvidencePath = Resolve-EvidencePath -Root $root -Path ([string]$attempt.evidence_artifact)
            if (-not (Test-Path -LiteralPath $attemptEvidencePath -PathType Leaf)) { throw "missing" }
            $attemptEvidenceHash = (Get-FileHash -LiteralPath $attemptEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($attemptEvidenceHash -ne [string]$attempt.evidence_sha256) { throw "hash" }
        } catch {
            Add-FailureCode -List $failureCodes -Code "attempt-evidence-invalid"
        }
    }
    $ledgerProjection = @($ledgerAttempts | ForEach-Object {
        [ordered]@{ attempt_id=$_.attempt_id; sequence=$_.sequence; operation_id=$_.operation_id; input_sha256=$_.input_sha256; workspace_before_sha256=$_.workspace_before_sha256; workspace_after_sha256=$_.workspace_after_sha256; changed_paths=@($_.changed_paths); status=$_.status; exit_code=$_.exit_code; failure_class=$_.failure_class; side_effects_observed=$_.side_effects_observed; recovery_action=$_.recovery_action; evidence_artifact=$_.evidence_artifact; evidence_sha256=$_.evidence_sha256 }
    }) | ConvertTo-Json -Depth 8 -Compress
    $reportProjection = @($reportAttempts | ForEach-Object {
        [ordered]@{ attempt_id=$_.attempt_id; sequence=$_.sequence; operation_id=$_.operation_id; input_sha256=$_.input_sha256; workspace_before_sha256=$_.workspace_before_sha256; workspace_after_sha256=$_.workspace_after_sha256; changed_paths=@($_.changed_paths); status=$_.status; exit_code=$_.exit_code; failure_class=$_.failure_class; side_effects_observed=$_.side_effects_observed; recovery_action=$_.recovery_action; evidence_artifact=$_.evidence_artifact; evidence_sha256=$_.evidence_sha256 }
    }) | ConvertTo-Json -Depth 8 -Compress
    if ($attemptLedger.schema -ne "antigravity-harness-attempt-ledger-v1" -or
        $attemptReport.schema -ne "antigravity-harness-completion-report-v1" -or
        [int]$attemptReport.ledger_version -ne [int]$attemptLedger.version -or
        [int]$attemptReport.attempt_count -ne $ledgerAttempts.Count -or
        [int]$attemptReport.failed_count -ne $ledgerFailures.Count -or
        [string]$attemptReport.status -ne $expectedStatus -or
        $ledgerProjection -ne $reportProjection -or
        $expectedStatus -eq "incomplete") {
        Add-FailureCode -List $failureCodes -Code "attempt-report-mismatch"
    }
}

# Re-read the explicitly referenced current inputs. Producer hashes are version
# integrity hints only and never establish an independent checker identity.
if ($claim) {
    try {
        if (-not $claim.contract -or -not $claim.test_result -or -not $claim.task_id -or -not $claim.task_attempt_id) { throw 'missing references' }
        $contractFullPath = Resolve-InsideProject -Root $root -Path ([string]$claim.contract.path)
        $contract = Get-Content -LiteralPath $contractFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($contract.schema -ne 'antigravity-harness-task-contract-v2' -or $contract.contract_id -ne $claim.task_id){Add-FailureCode $failureCodes 'contract-task-identity-mismatch'}
        if((Get-AgPath ([string]$contract.scope.project_root)) -ne (Get-AgPath $root)){Add-FailureCode $failureCodes 'contract-project-mismatch'}
        if ((Get-FileHash -LiteralPath $contractFullPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $claim.contract.sha256 -or
            (Get-Sha256Text -Text ([string]$contract.objective)) -ne $claim.objective_sha256) { Add-FailureCode $failureCodes 'contract-reference-mismatch' }
        if ($attemptLedger.task_id -ne $claim.task_id -or $attemptReport.task_id -ne $claim.task_id -or
            @($attemptLedger.attempts | Where-Object { $_.attempt_id -eq $claim.task_attempt_id -and $_.status -eq 'passed' }).Count -ne 1) { Add-FailureCode $failureCodes 'task-attempt-reference-mismatch' }
        if([string](@($attemptLedger.attempts|Sort-Object sequence)[-1].attempt_id) -ne $claim.task_attempt_id){Add-FailureCode $failureCodes 'attempt-not-current'}
        if ($attemptReport.ledger_sha256 -ne $claim.attempt_history.ledger_sha256) { Add-FailureCode $failureCodes 'report-ledger-reference-mismatch' }
        $resultPath = Resolve-InsideProject -Root $root -Path ([string]$claim.test_result.path)
        $resultHash = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($resultHash -ne $claim.test_result.sha256 -or $resultHash -ne $envelope.tests.result_sha256 -or
            $claim.test_result.run_id -ne $envelope.id -or
            (Resolve-InsideProject -Root $root -Path ([string]$envelope.tests.result_path)) -ne $resultPath) { Add-FailureCode $failureCodes 'test-result-reference-mismatch' }
        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($result.schema -ne 'antigravity-test-result-v1' -or @($result.cases).Count -eq 0 -or @($result.cases | Where-Object {$_.status -ne 'passed'}).Count) { Add-FailureCode $failureCodes 'structured-results-not-passed' }
        $passedIds=@($result.cases|Where-Object {$_.status -eq 'passed'}|ForEach-Object {[string]$_.id})
        foreach($criterion in @($contract.required_checks) + @($claim.acceptance_criteria|ForEach-Object {[string]$_.id})){if($criterion -and $criterion -notin $passedIds){Add-FailureCode $failureCodes 'required-check-missing'}}
        if(-not $envelope.task_binding -or $envelope.task_binding.task_id -ne $claim.task_id -or $envelope.task_binding.task_attempt_id -ne $claim.task_attempt_id -or $envelope.task_binding.contract_sha256 -ne $claim.contract.sha256){Add-FailureCode $failureCodes 'envelope-task-binding-mismatch'}
        if (@($envelope.inputs.after.source).Count -eq 0 -or @($envelope.inputs.after.tests).Count -eq 0) { Add-FailureCode $failureCodes 'verification-inputs-empty' }
        $completed=[DateTimeOffset]::Parse([string]$envelope.completed_at).UtcDateTime
        $started=[DateTimeOffset]::Parse([string]$envelope.created_at).UtcDateTime
        $resultItem=Get-Item -LiteralPath $resultPath
        if($resultItem.LastWriteTimeUtc -lt $started -or $resultItem.LastWriteTimeUtc -gt $completed){Add-FailureCode $failureCodes 'test-result-outside-run'}
        foreach($input in @($envelope.inputs.after.source)+@($envelope.inputs.after.tests)){
            $inputPath=Resolve-InsideProject -Root $root -Path ([string]$input.path)
            $items=@(Get-Item -LiteralPath $inputPath -Force)
            if($items[0].PSIsContainer){$items+=@(Get-ChildItem -LiteralPath $inputPath -Recurse -File -Force)}
            if(@($items|Where-Object {$_.LastWriteTimeUtc -gt $completed}).Count){Add-FailureCode $failureCodes 'input-written-after-verification'}
        }
        foreach($previous in @($claim.repair_of)){if($previous){$priorPath=Resolve-InsideProject -Root $root -Path ([string]$previous.path);if((Get-FileHash -LiteralPath $priorPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $previous.sha256){Add-FailureCode $failureCodes 'repair-history-replaced'}}}
        $seenOperations=@{}
        foreach($reference in @($claim.tool_operations)){
            if(-not $reference){continue}
            $operationPath=Get-AgPath ([string]$reference.path) $root
            if(-not(Test-AgWithin $operationPath $root)){
                $eventRoot=Get-AgPath ((Get-AgRoots).events)
                if(-not(Test-AgWithin $operationPath $eventRoot) -or -not(Test-Path -LiteralPath (Join-Path $eventRoot '.gemini-private'))){throw 'Operation outside evidence roots'}
            }
            if((Get-AgFileHash $operationPath) -ne $reference.sha256){Add-FailureCode $failureCodes 'operation-evidence-replaced'}
            $operation=Read-AgJson $operationPath;Assert-AgOperation $operation
            $operationStatus=Get-AgOperationStatus $operation
            if($operationStatus -ne $operation.status -or $operationStatus -in @('unresolved','unclassified')){Add-FailureCode $failureCodes 'operation-unresolved'}
            $attemptHashes=@($attemptLedger.attempts|ForEach-Object {Get-AgHash ([string]$_.attempt_id)})
            if($operation.operation_id -ne $reference.operation_id -or $operation.task_id_sha256 -ne (Get-AgHash ([string]$claim.task_id)) -or
               $operation.task_id_sha256 -ne $reference.task_id_sha256 -or $operation.attempt_id_sha256 -ne $reference.attempt_id_sha256 -or
               $operation.attempt_id_sha256 -notin $attemptHashes -or $operation.task_root_sha256 -ne (Get-AgHash $root.ToLowerInvariant())){Add-FailureCode $failureCodes 'operation-task-reference-mismatch'}
            if($seenOperations.ContainsKey([string]$operation.operation_id)){Add-FailureCode $failureCodes 'operation-reference-duplicate'}
            $seenOperations[[string]$operation.operation_id]=$true
        }
    } catch { Add-FailureCode $failureCodes 'explicit-chain-invalid' }
}

if (-not $currentWorkspace) {
    $currentWorkspace = [pscustomobject]@{
        algorithm = "unavailable"
        sha256 = Get-Sha256Text -Text ""
        files = 0
    }
}

$decisionStatus = if ($failureCodes.Count -eq 0) { "checking" } else { "unverified" }
$actorRoleValue = if ($claim) { [string]$claim.actor.role } else { "unknown" }
$requestedStatusValue = if ($claim) { [string]$claim.requested_status } else { "unknown" }
$claimReference = if ($claimFullPath) { Get-RelativeProjectPath -Root $root -Path $claimFullPath } else { "<unresolved>" }
$envelopeReference = if ($envelopeFullPath) { Get-RelativeProjectPath -Root $root -Path $envelopeFullPath } else { "<unresolved>" }

$decision = [ordered]@{
    schema = "antigravity-completion-decision-v1"
    id = $decisionId
    status = $decisionStatus
    task_id = if ($claim) { [string]$claim.task_id } else { '' }
    authority_status = "unverified"
    checked_at = (Get-Date).ToUniversalTime().ToString("o")
    summary = if ($decisionStatus -eq "checking") {
        "Completion evidence matches the current workspace, but checker identity has no trusted external attestation."
    } else {
        "Completion evidence is missing, stale, or unauthorized."
    }
    actor_role = $actorRoleValue
    requested_status = $requestedStatusValue
    claim = [ordered]@{
        path = $claimReference
        sha256 = $claimHash
    }
    envelope = [ordered]@{
        path = $envelopeReference
        sha256 = $envelopeHash
    }
    checks = [ordered]@{
        operation_coverage = if($claim -and @($claim.tool_operations).Count -gt 0){'explicit_subset'}else{'not_supplied'}
        operation_count = if($claim){@($claim.tool_operations).Count}else{0}
        hook_completeness_verified = $false
        independent_checker = if ($claim) { [bool]$claim.checker.independent } else { $false }
        source_changes = $sourceChanges
        test_changes = $testChanges
        protected_changes = $protectedChanges
        workspace_algorithm = $currentWorkspace.algorithm
        workspace_sha256 = $currentWorkspace.sha256
        attempt_history_present = [bool]($attemptLedger -and $attemptReport)
        attempt_count = if ($attemptReport) { [int]$attemptReport.attempt_count } else { 0 }
        failed_attempt_count = if ($attemptReport) { [int]$attemptReport.failed_count } else { 0 }
    }
    failures = $failureCodes.ToArray()
    script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

if ($ReadOnly) { $decision | ConvertTo-Json -Depth 16 -Compress; return }
$decisionDir = Join-Path $root ("artifacts\completion-gates\" + $decisionId)
$null=Resolve-InsideProject -Root $root -Path $decisionDir
New-Item -ItemType Directory -Force -Path $decisionDir | Out-Null
$decisionPath = Join-Path $decisionDir "decision.json"
$decisionHashPath = Join-Path $decisionDir "decision.sha256"
$decision | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $decisionPath -Encoding UTF8
$decisionHash = (Get-FileHash -LiteralPath $decisionPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $decisionHashPath -Value $decisionHash -Encoding ASCII

if ($decisionStatus -eq "unverified") {
    throw "Completion gate rejected the claim. Evidence: $decisionPath"
}

[ordered]@{
    status = "success"
    summary = "Completion evidence passed deterministic checks; trusted checker authority remains unverified."
    decision_status = $decisionStatus
    decision = $decisionPath
    decision_sha256 = $decisionHash
    decision_hash_file = $decisionHashPath
    artifacts = @($decisionPath, $decisionHashPath)
} | ConvertTo-Json -Depth 8 -Compress
