param(
    [string]$StateRoot = "",
    [string]$ProjectRoot = "",
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$TaskId,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$OperationId,
    [ValidatePattern('^$|^[a-f0-9]{64}$')][string]$InputSha256 = "",
    [string[]]$InputPaths = @(),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$AttemptId = "",
    [ValidateRange(-1, 2147483647)][int]$ExpectedVersion = -1
)

$ErrorActionPreference = "Stop"

function Get-DefaultStateRoot {
    if ($env:GEMINI_HARNESS_STATE_ROOT) { return $env:GEMINI_HARNESS_STATE_ROOT }
    return (Join-Path $env:USERPROFILE ".gemini\harness-state")
}
function Test-Within([string]$Candidate, [string]$Base) {
    $c = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $b = [IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    return $c.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($b + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Write-AtomicJson([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    $temp = Join-Path $parent (".tmp-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function New-Error([string]$Code, [string]$Summary) {
    [ordered]@{ status = "error"; error_code = $Code; summary = $Summary } | ConvertTo-Json -Compress
}
function Get-Sha256Text([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-Snapshot([string]$Root) {
    $excluded = @(".git", "artifacts", "harness-state", ".gemini-trash", ".codex-trash", "node_modules", "__pycache__")
    $prefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length).Replace('\', '/')
            if (@($relative -split '/')[0] -in $excluded) { return }
            [pscustomobject]@{ path=$relative; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        } | Sort-Object path
    )
    $serialized = ConvertTo-Json -InputObject @($files) -Depth 5 -Compress
    return [pscustomobject]@{ sha256=Get-Sha256Text $serialized; files=$files }
}
function Get-InputDigest([string]$Root, [string[]]$Paths, $Snapshot) {
    if ($Paths.Count -eq 0) { return $Snapshot.sha256 }
    $records = @($Paths | ForEach-Object {
        $raw = [string]$_
        $relative = $raw.Replace('\', '/').TrimStart('.', '/')
        if ([IO.Path]::IsPathRooted($raw) -or $relative -match '(^|/)\.\.(/|$)') { throw "InputPaths must be project-relative." }
        $full = Join-Path $Root $relative
        [pscustomobject]@{ path=$relative; sha256=if(Test-Path -LiteralPath $full -PathType Leaf){(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()}else{"missing"} }
    } | Sort-Object path)
    return Get-Sha256Text ($records | ConvertTo-Json -Depth 5 -Compress)
}

$lock = $null
try {
    if (-not $StateRoot) { $StateRoot = Get-DefaultStateRoot }
    $state = [IO.Path]::GetFullPath($StateRoot)
    $default = [IO.Path]::GetFullPath((Get-DefaultStateRoot))
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $hasMarker = Test-Path -LiteralPath (Join-Path $state ".gemini-private") -PathType Leaf
    if (-not (Test-Within $state $default) -and -not (Test-Within $state $tempRoot) -and -not $hasMarker) {
        Write-Output (New-Error "state_root_not_private" "Custom state root must be temporary or already marked private.")
        return
    }
    New-Item -ItemType Directory -Force -Path $state | Out-Null
    $marker = Join-Path $state ".gemini-private"
    if (-not (Test-Path -LiteralPath $marker)) { [IO.File]::WriteAllText($marker, "", (New-Object Text.UTF8Encoding($false))) }
    $root = Join-Path $state "attempt-ledgers"
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $ledgerPath = Join-Path $root ($TaskId + ".json")
    $lockPath = Join-Path $root ($TaskId + ".lock")
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    $resolvedProjectRoot = if ($ProjectRoot) { (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName } else { $null }
    if (-not $resolvedProjectRoot -and -not $InputSha256) { Write-Output (New-Error "input_evidence_required" "ProjectRoot or an observed input hash is required."); return }
    $snapshot = if ($resolvedProjectRoot) { Get-Snapshot $resolvedProjectRoot } else { [pscustomobject]@{sha256=$null;files=@()} }
    $resolvedInputSha = if ($resolvedProjectRoot) { Get-InputDigest $resolvedProjectRoot $InputPaths $snapshot } else { $InputSha256 }
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $ledger = if (Test-Path -LiteralPath $ledgerPath) {
        Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        [pscustomobject]@{ schema = "antigravity-harness-attempt-ledger-v1"; producer_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant(); last_update_script_sha256 = $null; task_id = $TaskId; project_root = $resolvedProjectRoot; version = 0; created_at = $now; updated_at = $now; attempts = @() }
    }
    if ($ExpectedVersion -ge 0 -and [int]$ledger.version -ne $ExpectedVersion) {
        Write-Output (New-Error "version_conflict" "Attempt ledger version changed.")
        return
    }
    if (-not $AttemptId) { $AttemptId = "attempt-" + [guid]::NewGuid().ToString("N").Substring(0, 12) }
    if (@($ledger.attempts | Where-Object { $_.attempt_id -eq $AttemptId }).Count -gt 0) {
        Write-Output (New-Error "attempt_id_conflict" "Attempt ID already exists.")
        return
    }
    $attempts = @($ledger.attempts)
    $attempts += [pscustomobject]@{
        attempt_id = $AttemptId
        sequence = $attempts.Count + 1
        operation_id = $OperationId
        input_sha256 = $resolvedInputSha
        workspace_before_sha256 = $snapshot.sha256
        workspace_before = $snapshot.files
        workspace_after_sha256 = $null
        changed_paths = @()
        status = "running"
        started_at = $now
        completed_at = $null
        exit_code = $null
        failure_class = $null
        side_effects_observed = $false
        recovery_action = $null
        evidence_artifact = $null
        evidence_sha256 = $null
    }
    $ledger.attempts = $attempts
    $ledger.version = [int]$ledger.version + 1
    $ledger.updated_at = $now
    Write-AtomicJson $ledgerPath $ledger
    [ordered]@{ status = "success"; path = $ledgerPath; task_id = $TaskId; attempt_id = $AttemptId; attempt_sequence = $attempts.Count; ledger_version = $ledger.version } | ConvertTo-Json -Compress
} catch {
    New-Error "attempt_creation_failed" "Attempt record could not be created."
} finally {
    if ($lock) { $lock.Dispose() }
}
