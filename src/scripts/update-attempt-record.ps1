param(
    [Parameter(Mandatory = $true)][string]$LedgerPath,
    [Parameter(Mandatory = $true)][string]$AttemptId,
    [Parameter(Mandatory = $true)][ValidateSet("passed", "failed", "rejected", "blocked", "stopped")][string]$Status,
    [ValidateRange(-1, 2147483647)][int]$ExpectedVersion = -1,
    [Nullable[int]]$ExitCode = $null,
    [string]$FailureClass = "",
    [switch]$SideEffectsObserved,
    [string]$RecoveryAction = "",
    [string]$EvidenceArtifact = ""
)

$ErrorActionPreference = "Stop"
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
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        $relative=$_.FullName.Substring($prefix.Length).Replace('\','/')
        if(@($relative -split '/')[0] -in $excluded){return}
        [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    } | Sort-Object path)
    $serialized = ConvertTo-Json -InputObject @($files) -Depth 5 -Compress
    [pscustomobject]@{sha256=Get-Sha256Text $serialized;files=$files}
}

$lock = $null
try {
    $path = (Resolve-Path -LiteralPath $LedgerPath).Path
    $stateRoot = Split-Path -Parent (Split-Path -Parent $path)
    if (-not (Test-Path -LiteralPath (Join-Path $stateRoot ".gemini-private") -PathType Leaf)) {
        Write-Output (New-Error "state_root_not_private" "Attempt ledger is not under a marked private state root.")
        return
    }
    $lockPath = [IO.Path]::ChangeExtension($path, ".lock")
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $ledger = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($ledger.schema -ne "antigravity-harness-attempt-ledger-v1") { throw "Unsupported ledger schema." }
    if ($ExpectedVersion -ge 0 -and [int]$ledger.version -ne $ExpectedVersion) {
        Write-Output (New-Error "version_conflict" "Attempt ledger version changed.")
        return
    }
    $attempts = @($ledger.attempts)
    $target = @($attempts | Where-Object { $_.attempt_id -eq $AttemptId })
    if ($target.Count -ne 1) { Write-Output (New-Error "attempt_not_found" "Attempt ID was not found."); return }
    if ($target[0].status -ne "running") { Write-Output (New-Error "attempt_terminal" "Terminal attempt records are immutable."); return }
    if ($Status -in @("failed", "rejected", "blocked") -and -not $FailureClass) {
        Write-Output (New-Error "failure_class_required" "Failure class is required for unsuccessful attempts.")
        return
    }
    if (-not $EvidenceArtifact) {
        Write-Output (New-Error "evidence_artifact_required" "A terminal attempt requires an evidence artifact.")
        return
    }
    try {
        $evidenceFullPath = if ([IO.Path]::IsPathRooted($EvidenceArtifact)) {
            [IO.Path]::GetFullPath($EvidenceArtifact)
        } elseif ($ledger.project_root) {
            [IO.Path]::GetFullPath((Join-Path ([string]$ledger.project_root) $EvidenceArtifact))
        } else {
            [IO.Path]::GetFullPath((Join-Path $stateRoot $EvidenceArtifact))
        }
        if (-not (Test-Path -LiteralPath $evidenceFullPath -PathType Leaf)) { throw "missing" }
        $evidenceSha256 = (Get-FileHash -LiteralPath $evidenceFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    } catch {
        Write-Output (New-Error "evidence_artifact_missing" "Evidence artifact does not exist or is not readable.")
        return
    }
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $changedPaths = @()
    $workspaceAfterSha = $null
    if ($ledger.project_root -and ($target[0].PSObject.Properties.Name -contains "workspace_before")) {
        $after = Get-Snapshot ([string]$ledger.project_root)
        $workspaceAfterSha = $after.sha256
        $beforeMap=@{}; foreach($item in @($target[0].workspace_before)){$beforeMap[[string]$item.path]=$item}
        $afterMap=@{}; foreach($item in @($after.files)){$afterMap[[string]$item.path]=$item}
        $changedPaths=@($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique | Where-Object {
            -not $beforeMap.ContainsKey($_) -or -not $afterMap.ContainsKey($_) -or [string]$beforeMap[$_].sha256 -ne [string]$afterMap[$_].sha256
        })
    }
    $target[0].status = $Status
    $target[0].completed_at = $now
    $target[0].exit_code = if ($null -eq $ExitCode) { $null } else { [int]$ExitCode }
    $target[0].failure_class = if ($FailureClass) { $FailureClass.Trim() } else { $null }
    $target[0].workspace_after_sha256 = $workspaceAfterSha
    $target[0].changed_paths = $changedPaths
    $target[0].side_effects_observed = [bool]($SideEffectsObserved -or $changedPaths.Count -gt 0)
    $target[0].recovery_action = if ($RecoveryAction) { $RecoveryAction.Trim().Substring(0, [Math]::Min(240, $RecoveryAction.Trim().Length)) } else { $null }
    $target[0].evidence_artifact = if ($EvidenceArtifact) { $EvidenceArtifact.Trim() } else { $null }
    $target[0].evidence_sha256 = $evidenceSha256
    $ledger.attempts = $attempts
    $ledger.version = [int]$ledger.version + 1
    $ledger.updated_at = $now
    $ledger.last_update_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-AtomicJson $path $ledger
    [ordered]@{ status = "success"; attempt_status = $Status; ledger_version = $ledger.version; path = $path } | ConvertTo-Json -Compress
} catch {
    New-Error "attempt_update_failed" "Attempt record could not be updated."
} finally {
    if ($lock) { $lock.Dispose() }
}
