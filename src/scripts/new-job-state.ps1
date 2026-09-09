param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ContractPath,
    [string]$StateRoot = "",
    [string]$JobId = "",
    [string]$InitialNextAction = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DefaultStateRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:GEMINI_HARNESS_STATE_ROOT)) {
        return $env:GEMINI_HARNESS_STATE_ROOT
    }
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw "StateRoot is required when USERPROFILE is unavailable."
    }
    return (Join-Path $env:USERPROFILE ".gemini\harness-state")
}

function Test-PathWithin {
    param([string]$Candidate, [string]$Base)
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $baseFull = [System.IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    return $candidateFull.Equals($baseFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($baseFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Write-JsonNoBom {
    param(
        [string]$Path,
        $Value
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), $encoding)
}

try {
    $resolvedContractPath = (Resolve-Path -LiteralPath $ContractPath).Path
    $contract = Get-Content -LiteralPath $resolvedContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($contract.schema -ne "antigravity-harness-task-contract-v2") {
        throw "Unsupported task contract schema: $($contract.schema)"
    }

    if ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $StateRoot = Get-DefaultStateRoot
    }
    $resolvedStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
    $allowedStateRoots = @(
        [System.IO.Path]::GetFullPath((Get-DefaultStateRoot)),
        [System.IO.Path]::GetFullPath((Join-Path ([string]$contract.scope.project_root) "artifacts")),
        [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    )
    if (-not @($allowedStateRoots | Where-Object { Test-PathWithin -Candidate $resolvedStateRoot -Base $_ }).Count) {
        throw "StateRoot must be the canonical Gemini harness-state root, the project artifacts directory, or the system temporary directory."
    }
    New-Item -ItemType Directory -Force -Path $resolvedStateRoot | Out-Null
    $privateMarker = Join-Path $resolvedStateRoot ".gemini-private"
    if (-not (Test-Path -LiteralPath $privateMarker -PathType Leaf)) {
        [System.IO.File]::WriteAllText($privateMarker, "", (New-Object System.Text.UTF8Encoding($false)))
    }

    if ([string]::IsNullOrWhiteSpace($JobId)) {
        $JobId = "job-" + (Get-Date).ToString("yyyyMMdd-HHmmssfff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    }
    if ($JobId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') {
        throw "JobId must contain only letters, numbers, dots, underscores, or hyphens and be at most 96 characters."
    }

    $jobsRoot = Join-Path $resolvedStateRoot "jobs"
    New-Item -ItemType Directory -Force -Path $jobsRoot | Out-Null
    $jobPath = Join-Path $jobsRoot ($JobId + ".json")
    if (Test-Path -LiteralPath $jobPath) {
        throw "Job state already exists: $JobId"
    }

    $now = (Get-Date).ToUniversalTime().ToString("o")
    $job = [ordered]@{
        schema = "antigravity-harness-job-state-v2"
        job_id = $JobId
        contract_id = $contract.contract_id
        contract_path = $resolvedContractPath
        project_root = $contract.scope.project_root
        objective_sha256 = Get-Sha256Text -Value $contract.objective
        attempt_id = [guid]::NewGuid().ToString("N")
        state = "drafted"
        version = 1
        created_at = $now
        updated_at = $now
        last_progress = $null
        next_action = if ([string]::IsNullOrWhiteSpace($InitialNextAction)) { $null } else { $InitialNextAction.Trim() }
        blockers = @()
        stop_reason = $null
        verification = [ordered]@{
            verified_commit = $null
            workspace_fingerprint = $null
            artifact = $null
        }
        history = @(
            [ordered]@{
                version = 1
                timestamp = $now
                from = $null
                to = "drafted"
                summary = "job state created"
            }
        )
    }

    $temporaryPath = $jobPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    Write-JsonNoBom -Path $temporaryPath -Value $job
    Move-Item -LiteralPath $temporaryPath -Destination $jobPath

    [ordered]@{
        status = "success"
        job_id = $JobId
        path = $jobPath
        state = "drafted"
        version = 1
        attempt_id = $job.attempt_id
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    [ordered]@{
        status = "error"
        error_code = "job_state_creation_failed"
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 4 -Compress
}
