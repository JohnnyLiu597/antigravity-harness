param(
    [string]$ProjectRoot = ".",
    [string]$StateRoot = "",
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Objective,
    [string[]]$NonGoals = @(),
    [ValidateSet("read_only", "write")]
    [string]$Access = "write",
    [string[]]$AllowedPaths = @(),
    [string[]]$DeniedPaths = @(),
    [ValidateRange(0, 2147483647)]
    [int]$MaxFiles = 10,
    [ValidateRange(0, 2147483647)]
    [int]$MaxAddedLines = 500,
    [switch]$AllowDependencyChanges,
    [switch]$AllowArchitectureChanges,
    [string[]]$RequiredChecks = @(),
    [string[]]$ApprovalTriggers = @(
        "scope_expansion",
        "dependency_change",
        "architecture_change",
        "destructive_action",
        "external_write",
        "deployment",
        "publication"
    ),
    [string]$ContractId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-NormalizedRelativePath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Scope paths cannot be empty."
    }

    $candidate = $Value.Trim()
    if ([System.IO.Path]::IsPathRooted($candidate) -or $candidate -match '^[A-Za-z]:') {
        throw "Scope path must be project-relative: $Value"
    }

    $hadTrailingSeparator = $candidate.EndsWith("/") -or $candidate.EndsWith("\")
    $candidate = $candidate.Replace("\", "/")
    while ($candidate.StartsWith("./", [System.StringComparison]::Ordinal)) {
        $candidate = $candidate.Substring(2)
    }
    $candidate = $candidate -replace '/+', '/'

    $segments = @($candidate.Split('/') | Where-Object { $_ -ne "" -and $_ -ne "." })
    if (@($segments | Where-Object { $_ -eq ".." }).Count -gt 0) {
        throw "Scope path cannot traverse outside the project: $Value"
    }
    if (@($segments | Where-Object { $_ -match ':' }).Count -gt 0) {
        throw "Scope path contains an invalid drive or stream separator: $Value"
    }

    if ($segments.Count -eq 0) {
        return "."
    }

    $normalized = $segments -join "/"
    if ($hadTrailingSeparator) {
        $normalized += "/"
    }
    return $normalized
}

function ConvertTo-UniqueTrimmedStrings {
    param([string[]]$Values)
    return @($Values | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) { $_.Trim() }
    } | Sort-Object -Unique)
}

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

function Write-JsonNoBom {
    param(
        [string]$Path,
        $Value
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $json = $Value | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Get-WorkspaceBaseline {
    param([string]$Root)
    $excluded = @(".git", "artifacts", "harness-state", ".gemini-trash", ".codex-trash", "node_modules", "__pycache__")
    $prefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $records = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $relative = $_.FullName.Substring($prefix.Length).Replace('\', '/')
                if (@($relative -split '/')[0] -in $excluded) { return }
                $lineCount = 0
                try { $lineCount = @(Get-Content -LiteralPath $_.FullName -Encoding UTF8 -ErrorAction Stop).Count } catch {}
                [pscustomobject]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); lines = $lineCount }
            } | Sort-Object path
    )
    $serialized = ConvertTo-Json -InputObject @($records) -Depth 5 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$serialized)))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    return [ordered]@{ workspace_sha256 = $fingerprint; files = $records; excluded_roots = $excluded }
}

try {
    $resolvedProjectRoot = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
    if ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $StateRoot = Get-DefaultStateRoot
    }
    $resolvedStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
    $allowedStateRoots = @(
        [System.IO.Path]::GetFullPath((Get-DefaultStateRoot)),
        [System.IO.Path]::GetFullPath((Join-Path $resolvedProjectRoot "artifacts")),
        [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    )
    if (-not @($allowedStateRoots | Where-Object { Test-PathWithin -Candidate $resolvedStateRoot -Base $_ }).Count) {
        throw "StateRoot must be the canonical Gemini harness-state root, the project artifacts directory, or the system temporary directory."
    }

    if ([string]::IsNullOrWhiteSpace($ContractId)) {
        $ContractId = "task-" + (Get-Date).ToString("yyyyMMdd-HHmmssfff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    }
    if ($ContractId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') {
        throw "ContractId must contain only letters, numbers, dots, underscores, or hyphens and be at most 96 characters."
    }

    $normalizedAllowed = @($AllowedPaths | ForEach-Object { ConvertTo-NormalizedRelativePath -Value $_ } | Sort-Object -Unique)
    $normalizedDenied = @($DeniedPaths | ForEach-Object { ConvertTo-NormalizedRelativePath -Value $_ } | Sort-Object -Unique)
    if ($Access -eq "write" -and $normalizedAllowed.Count -eq 0) {
        throw "A write task contract requires at least one allowed path. Use Access read_only for a no-write contract."
    }
    if ($Access -eq "read_only" -and $normalizedAllowed.Count -gt 0) {
        throw "A read_only task contract cannot declare writable allowed paths."
    }

    $normalizedNonGoals = ConvertTo-UniqueTrimmedStrings -Values $NonGoals
    $normalizedChecks = ConvertTo-UniqueTrimmedStrings -Values $RequiredChecks
    $normalizedTriggers = @(ConvertTo-UniqueTrimmedStrings -Values $ApprovalTriggers | ForEach-Object { $_.ToLowerInvariant() })
    $invalidTriggers = @($normalizedTriggers | Where-Object { $_ -notmatch '^[a-z][a-z0-9_-]{0,63}$' })
    if ($invalidTriggers.Count -gt 0) {
        throw "Invalid approval trigger: $($invalidTriggers[0])"
    }

    New-Item -ItemType Directory -Force -Path $resolvedStateRoot | Out-Null
    $privateMarker = Join-Path $resolvedStateRoot ".gemini-private"
    if (-not (Test-Path -LiteralPath $privateMarker -PathType Leaf)) {
        [System.IO.File]::WriteAllText($privateMarker, "", (New-Object System.Text.UTF8Encoding($false)))
    }

    $contractsRoot = Join-Path $resolvedStateRoot "contracts"
    New-Item -ItemType Directory -Force -Path $contractsRoot | Out-Null
    $contractPath = Join-Path $contractsRoot ($ContractId + ".json")
    if (Test-Path -LiteralPath $contractPath) {
        throw "Task contract already exists: $ContractId"
    }

    $baseline = Get-WorkspaceBaseline -Root $resolvedProjectRoot
    $contract = [ordered]@{
        schema = "antigravity-harness-task-contract-v2"
        producer_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        contract_id = $ContractId
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        status = "draft"
        objective = $Objective.Trim()
        non_goals = @($normalizedNonGoals)
        scope = [ordered]@{
            project_root = $resolvedProjectRoot
            access = $Access
            allowed_paths = @($normalizedAllowed)
            denied_paths = @($normalizedDenied)
        }
        change_budget = [ordered]@{
            max_files = $MaxFiles
            max_added_lines = $MaxAddedLines
            dependency_changes = [bool]$AllowDependencyChanges
            architecture_changes = [bool]$AllowArchitectureChanges
        }
        required_checks = @($normalizedChecks)
        approval_triggers = @($normalizedTriggers)
        baseline = $baseline
    }

    $temporaryPath = $contractPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    Write-JsonNoBom -Path $temporaryPath -Value $contract
    Move-Item -LiteralPath $temporaryPath -Destination $contractPath

    [ordered]@{
        status = "success"
        contract_id = $ContractId
        path = $contractPath
        access = $Access
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    [ordered]@{
        status = "error"
        error_code = "task_contract_creation_failed"
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 4 -Compress
}
