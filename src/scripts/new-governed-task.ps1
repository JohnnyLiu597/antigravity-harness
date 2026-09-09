param(
    [string]$ProjectRoot = ".",
    [string]$StateRoot = "",
    [string]$RegistryRoot = "",
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$LogicalTaskId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Objective,
    [string[]]$NonGoals = @(),
    [string[]]$AllowedPaths = @(),
    [string[]]$DeniedPaths = @(),
    [int]$MaxFiles = 10,
    [int]$MaxAddedLines = 500,
    [string[]]$RequiredChecks = @(),
    [string]$PreviousTaskRoot = "",
    [string]$TransitionReason = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PathHash([string]$Path) {
    $normalized = [IO.Path]::GetFullPath($Path).TrimEnd('\','/').ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-TextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Write-JsonNoBom([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
}

try {
    $root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
    if (-not $StateRoot) { $StateRoot = Join-Path $root "harness-state" }
    if (-not $RegistryRoot) {
        if (-not $env:USERPROFILE) { throw "RegistryRoot is required when USERPROFILE is unavailable." }
        $RegistryRoot = Join-Path $env:USERPROFILE ".gemini\harness-state\task-roots"
    }
    $state = [IO.Path]::GetFullPath($StateRoot)
    $registry = [IO.Path]::GetFullPath($RegistryRoot)
    New-Item -ItemType Directory -Force -Path $registry | Out-Null
    $registryMarker = Join-Path $registry ".gemini-private"
    if (-not (Test-Path -LiteralPath $registryMarker -PathType Leaf)) {
        [IO.File]::WriteAllText($registryMarker, "", (New-Object Text.UTF8Encoding($false)))
    }
    $rootHash = Get-PathHash $root
    $registryPath = Join-Path $registry ($LogicalTaskId + ".json")
    $intentMaterial = [ordered]@{
        objective = $Objective.Trim()
        non_goals = @($NonGoals | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        allowed_paths = @($AllowedPaths | ForEach-Object { ([string]$_).Trim().Replace('\','/') } | Where-Object { $_ } | Sort-Object -Unique)
        denied_paths = @($DeniedPaths | ForEach-Object { ([string]$_).Trim().Replace('\','/') } | Where-Object { $_ } | Sort-Object -Unique)
        required_checks = @($RequiredChecks | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        max_files = $MaxFiles
        max_added_lines = $MaxAddedLines
    }
    $intentSha256 = Get-TextHash (ConvertTo-Json -InputObject $intentMaterial -Depth 8 -Compress)
    $intentRoot = Join-Path $registry "intents"
    $intentPath = Join-Path $intentRoot ($intentSha256 + ".json")
    $existingIntent = if (Test-Path -LiteralPath $intentPath -PathType Leaf) { Get-Content -LiteralPath $intentPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    if ($existingIntent -and [string]$existingIntent.logical_task_id -ne $LogicalTaskId) {
        [ordered]@{
            status = "error"
            error_code = "task_intent_already_active"
            error = "An equivalent governed task intent is already active; resume its LogicalTaskId instead of renaming the task."
            existing_logical_task_id = [string]$existingIntent.logical_task_id
            existing_task_root_sha256 = [string]$existingIntent.active_task_root_sha256
            task_intent_sha256 = $intentSha256
        } | ConvertTo-Json -Compress
        return
    }
    $existing = if (Test-Path -LiteralPath $registryPath -PathType Leaf) { Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $generation = 1
    $previousHash = $null

    if ($existing -and [string]$existing.active_task_root_sha256 -ne $rootHash) {
        if (-not $PreviousTaskRoot -or -not $TransitionReason.Trim()) {
            throw [Management.Automation.ErrorRecord]::new([InvalidOperationException]::new("The logical task already has a different active TaskRoot; PreviousTaskRoot and TransitionReason are required."), "task_root_transition_required", [Management.Automation.ErrorCategory]::InvalidOperation, $root)
        }
        $previous = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $PreviousTaskRoot).Path -Force).FullName
        $previousHash = Get-PathHash $previous
        if ($previousHash -ne [string]$existing.active_task_root_sha256) { throw "PreviousTaskRoot does not match the registered active TaskRoot." }
        $generation = [int]$existing.generation + 1
    } elseif ($existing) {
        throw "The governed task root is already registered; resume the existing task instead of creating a second contract."
    } elseif ($PreviousTaskRoot) {
        throw "PreviousTaskRoot cannot be supplied when no logical task registry entry exists."
    }

    $contractRaw = & (Join-Path $PSScriptRoot "new-task-contract.ps1") -ProjectRoot $root -StateRoot $state -Objective $Objective -NonGoals $NonGoals -AllowedPaths $AllowedPaths -DeniedPaths $DeniedPaths -MaxFiles $MaxFiles -MaxAddedLines $MaxAddedLines -RequiredChecks $RequiredChecks -ContractId $LogicalTaskId
    $contractResult = $contractRaw | ConvertFrom-Json
    if ($contractResult.status -ne "success") { throw "Task contract bootstrap failed: $($contractResult.error)" }

    $manifest = [ordered]@{
        schema = "antigravity-governed-task-root-v1"
        producer_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        logical_task_id = $LogicalTaskId
        task_intent_sha256 = $intentSha256
        generation = $generation
        task_root_sha256 = $rootHash
        previous_task_root_sha256 = $previousHash
        transition_reason = if ($previousHash) { $TransitionReason.Trim() } else { $null }
        contract_path = [IO.Path]::GetFullPath([string]$contractResult.path)
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $manifestPath = Join-Path $state "task-root.json"
    Write-JsonNoBom $manifestPath $manifest
    $registryRecord = [ordered]@{schema="antigravity-governed-task-registry-v1";logical_task_id=$LogicalTaskId;generation=$generation;active_task_root_sha256=$rootHash;previous_task_root_sha256=$previousHash;updated_at=(Get-Date).ToUniversalTime().ToString('o')}
    Write-JsonNoBom $registryPath $registryRecord
    $intentRecord = [ordered]@{schema="antigravity-governed-task-intent-v1";task_intent_sha256=$intentSha256;logical_task_id=$LogicalTaskId;generation=$generation;active_task_root_sha256=$rootHash;updated_at=(Get-Date).ToUniversalTime().ToString('o')}
    Write-JsonNoBom $intentPath $intentRecord
    [ordered]@{status="success";logical_task_id=$LogicalTaskId;generation=$generation;manifest=$manifestPath;contract=[string]$contractResult.path} | ConvertTo-Json -Compress
} catch {
    $code = if ($_.FullyQualifiedErrorId -like 'task_root_transition_required*') { 'task_root_transition_required' } else { 'governed_task_creation_failed' }
    [ordered]@{status="error";error_code=$code;error=$_.Exception.Message} | ConvertTo-Json -Compress
}
