[CmdletBinding()]
param(
    [string]$GeminiHome = "$env:USERPROFILE\.gemini",
    [string]$ProjectRoot = "",
    [switch]$DryRun,
    [switch]$NoBackup,
    [string]$TransactionRoot = "",
    [string]$RollbackManifest = "",
    [ValidateRange(0,10000)][int]$TestFailAfterFiles = 0
)

$ErrorActionPreference = "Stop"

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-NoUnexpectedStreams $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-NoUnexpectedStreams([string]$Path) {
    if(@(Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop | Where-Object {$_.Stream -notin @(':$DATA','Zone.Identifier')}).Count){throw 'Unexpected alternate data stream; payload integrity unavailable.'}
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tempPath = Join-Path $parent ((Split-Path -Leaf $Path) + ".tmp-" + [guid]::NewGuid().ToString("N"))
    $encoding = New-Object System.Text.UTF8Encoding($false)
    Assert-InGeminiHome -Path $Path
    $bytes=$encoding.GetBytes(($Value | ConvertTo-Json -Depth 12))
    $stream=[IO.File]::Open($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tempPath,$Path,($Path+'.revision-'+[guid]::NewGuid().ToString('N')))}
    else {[IO.File]::Move($tempPath,$Path)}
}

if (-not (Test-Path -LiteralPath $GeminiHome -PathType Container)) {
    throw "Gemini home does not exist: $GeminiHome"
}
$GeminiHome = [System.IO.Path]::GetFullPath($GeminiHome)
$script:geminiRootPath = $GeminiHome
$script:geminiRootPrefix = $GeminiHome.TrimEnd('\') + '\'
$geminiHomeFingerprint = Get-StringSha256 -Value $GeminiHome.ToLowerInvariant()

function Assert-InGeminiHome {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    if($full -match '^\\\\' -or $full.Substring(2).Contains(':') -or $full -match '[. ]([\\/]|$)'){throw 'Unsafe runtime path alias or ADS.'}
    if ($full -ne $script:geminiRootPath -and
        -not $full.StartsWith($script:geminiRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside Gemini home: $full"
    }

    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to traverse a runtime reparse point: $cursor"
            }
        }
        $next = Split-Path -Parent $cursor
        if (-not $next -or $next -eq $cursor) { break }
        $cursor = $next
    }
}

function Get-RelativeRuntimePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    Assert-InGeminiHome -Path $full
    return $full.Substring($script:geminiRootPrefix.Length)
}

function Test-PrivateRuntimeTarget {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $paths = @($RelativePath)
    if ($RelativePath -match '^skills[\\/](.+)$') { $paths += ('config\skills\' + $Matches[1]) }
    elseif ($RelativePath -match '^config[\\/]skills[\\/](.+)$') { $paths += ('skills\' + $Matches[1]) }
    foreach ($candidatePath in $paths) {
        $segments = $candidatePath -split '[\\/]'
        $cursor = $GeminiHome
        for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
            $cursor = Join-Path $cursor $segments[$index]
            Assert-InGeminiHome $cursor
            if (Test-Path -LiteralPath (Join-Path $cursor ".gemini-private") -PathType Leaf) { return $true }
        }
    }
    return $false
}

function Assert-PayloadRelativePath([string]$Relative) {
    if($Relative -match '(^[\\/]|:|(^|[\\/])\.\.?([\\/]|$)|[. ]([\\/]|$))' -or
       $Relative -notmatch '^(AGENTS\.md|GEMINI\.md|harness\.(capabilities|components)\.json|(?:agents|skills|scripts|templates|schemas|harness-evals|config[\\/]skills)[\\/][a-zA-Z0-9_. \\/-]+)$' -or
       $Relative -match '(^|[\\/])(config\.json|auth\.json|mcp_config\.json|\.gemini-private|harness-state|runs|adapters)([\\/]|$)'){throw 'Manifest target is not a normal harness payload path.'}
}
function Assert-TransactionLocation([string]$ManifestPath) {
    Assert-InGeminiHome -Path $ManifestPath
    $folder=Split-Path -Parent $ManifestPath
    if((Split-Path -Parent $folder) -ine $GeminiHome -or (Split-Path -Leaf $folder) -notmatch '^backup-[a-zA-Z0-9-]+-antigravity-harness-sync$' -or (Split-Path -Leaf $ManifestPath) -cne 'sync-transaction.json'){throw 'Transaction must be in the owned runtime backup store.'}
}
function Assert-RollbackEntries($Transaction,[string]$ManifestPath) {
    Assert-TransactionLocation $ManifestPath
    $seen=@{};$transactionRootPath=Split-Path -Parent $ManifestPath
    foreach($entry in @($Transaction.files)) {
        $relative=[string]$entry.relative_path;Assert-PayloadRelativePath $relative
        if($seen.ContainsKey($relative)){throw 'Duplicate rollback target.'};$seen[$relative]=$true
        $target=Join-Path $GeminiHome $relative;Assert-InGeminiHome $target
        if(Test-PrivateRuntimeTarget $relative){throw 'Rollback target is now private.'}
        if($entry.target_existed -isnot [bool]){throw 'Invalid rollback target existence flag.'}
        if($entry.target_existed) {
            if([string]$entry.backup_relative_path -ine (Join-Path 'files' $relative)){throw 'Backup path does not match the declared payload path.'}
            $backup=Join-Path $transactionRootPath ([string]$entry.backup_relative_path);Assert-InGeminiHome $backup
            if(-not(Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-FileSha256 $backup) -cne [string]$entry.target_sha256_before){throw 'Backup missing or changed.'}
        } elseif([string]$entry.backup_relative_path){throw 'Unexpected backup for new file.'}
        if(Test-Path -LiteralPath $target) {
            if(-not(Test-Path -LiteralPath $target -PathType Leaf)){throw 'Rollback target is no longer a file.'}
            $current=Get-FileSha256 $target
            if($current -cne [string]$entry.source_sha256 -and $current -cne [string]$entry.target_sha256_before){throw 'Current target changed after install; refusing rollback overwrite.'}
        }
    }
}

function Invoke-TransactionRollback {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$ManifestPath
    )

    $transactionRootPath = Split-Path -Parent $ManifestPath
    Assert-RollbackEntries $Transaction $ManifestPath
    if($Transaction.status -eq 'rolled-back'){return [pscustomobject]@{restored=0;removed=0}}
    $displacedRoot=Join-Path $transactionRootPath ('displaced\'+[guid]::NewGuid().ToString('N'))
    $restored = 0
    $removed = 0
    $Transaction.rollback.attempted = $true
    $Transaction.rollback.started_at = (Get-Date).ToUniversalTime().ToString("o")
    $Transaction.rollback.status = "running"
    Write-JsonAtomically -Path $ManifestPath -Value $Transaction

    try {
        foreach ($entry in @($Transaction.files)) {
            $relative = [string]$entry.relative_path
            $target = Join-Path $GeminiHome $relative
            Assert-InGeminiHome -Path $target
            if([string]$entry.state -eq 'prepared'){$entry.rollback_state='untouched';continue}
            if(Test-Path -LiteralPath $target -PathType Leaf) {
                $displaced=Join-Path $displacedRoot $relative;Assert-InGeminiHome $displaced
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $displaced)|Out-Null
                Move-Item -LiteralPath $target -Destination $displaced
            }
            if ([bool]$entry.target_existed) {
                $backup = Join-Path $transactionRootPath ([string]$entry.backup_relative_path)
                if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
                    throw "Transaction backup is missing for $relative"
                }
                $backupHash = Get-FileSha256 -Path $backup
                if ($backupHash -ne [string]$entry.target_sha256_before) {
                    throw "Transaction backup hash mismatch for $relative"
                }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                $restoreSwitch=Join-Path $transactionRootPath ('restore-switch\'+[guid]::NewGuid().ToString('N')+'\'+$relative)
                Assert-InGeminiHome $restoreSwitch
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $restoreSwitch)|Out-Null
                Copy-Item -LiteralPath $backup -Destination $restoreSwitch
                if((Get-FileSha256 $restoreSwitch) -cne [string]$entry.target_sha256_before){throw 'Rollback staging mismatch.'}
                Assert-InGeminiHome $target
                [IO.File]::Move($restoreSwitch,$target)
                if ((Get-FileSha256 -Path $target) -ne [string]$entry.target_sha256_before) {
                    throw "Rollback restore hash mismatch for $relative"
                }
                $entry.rollback_state = "restored"
                $restored++
            } else {
                if (Test-Path -LiteralPath $target) {
                    throw "Rollback target is no longer a file: $relative"
                }
                $removed++
                $entry.rollback_state = "retained-displaced"
            }
        }
        # Empty directories and displaced candidates are deliberately retained.
        $Transaction.status = "rolled-back"
        $Transaction.rollback.status = "rolled-back"
        $Transaction.rollback.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        $Transaction.rollback.restored_files = $restored
        $Transaction.rollback.removed_files = $removed
        Write-JsonAtomically -Path $ManifestPath -Value $Transaction
    } catch {
        $Transaction.status = "rollback-failed"
        $Transaction.rollback.status = "rollback-failed"
        $Transaction.rollback.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        $Transaction.rollback.error_sha256 = Get-StringSha256 -Value $_.Exception.Message
        Write-JsonAtomically -Path $ManifestPath -Value $Transaction
        throw
    }

    return [pscustomobject]@{
        restored = $restored
        removed = $removed
    }
}

Assert-InGeminiHome $GeminiHome
if(Test-Path -LiteralPath (Join-Path $GeminiHome '.gemini-private') -PathType Leaf){throw 'Runtime root is private-marked; neither installation nor rollback may modify it.'}
if($TestFailAfterFiles -gt 0){
    $testPrefix=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    $longTestPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $GeminiHome.StartsWith($testPrefix,[StringComparison]::OrdinalIgnoreCase) -and -not $GeminiHome.StartsWith($longTestPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Failure injection restricted to TEMP fixtures.'}
}
if($NoBackup){throw '-NoBackup is disabled: v4 requires recoverable installation.'}
$syncMutex=New-Object Threading.Mutex($false,('Local\AntigravityHarnessSync-'+$geminiHomeFingerprint))
$syncLocked=$false
try {
    try {$syncLocked=$syncMutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$syncLocked=$true}
    if(-not $syncLocked){throw 'Runtime sync busy; no changes made.'}
if ($RollbackManifest) {
    if ($DryRun -or $NoBackup -or $TransactionRoot) {
        throw "-RollbackManifest cannot be combined with -DryRun, -NoBackup, or -TransactionRoot."
    }
    $manifestPath = (Resolve-Path -LiteralPath $RollbackManifest).Path
    Assert-TransactionLocation $manifestPath
    $transaction = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$transaction.schema -ne "antigravity-harness-sync-transaction-v2") {
        throw "Unsupported sync transaction manifest schema."
    }
    if ([string]$transaction.gemini_home_sha256 -ne $geminiHomeFingerprint) {
        throw "Transaction manifest belongs to a different Gemini home."
    }
    $rollbackResult = Invoke-TransactionRollback -Transaction $transaction -ManifestPath $manifestPath
    [ordered]@{
        status = "rolled-back"
        summary = "Runtime sync transaction rolled back."
        gemini_home = $GeminiHome
        transaction_manifest = $manifestPath
        restored_files = $rollbackResult.restored
        removed_files = $rollbackResult.removed
        removal_policy = 'Moved to retained transaction displaced archive; no permanent deletion.'
        source_fingerprint = [string]$transaction.source_fingerprint
    } | ConvertTo-Json -Depth 8 -Compress
    return
}

if (-not $ProjectRoot) {
    $ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
} else {
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root does not exist: $ProjectRoot"
    }
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}

$srcRoot = Join-Path $ProjectRoot "src"
if (-not (Test-Path -LiteralPath $srcRoot -PathType Container)) {
    throw "Missing source payload: $srcRoot"
}
$srcRoot = [System.IO.Path]::GetFullPath($srcRoot)
$srcPrefix = $srcRoot.TrimEnd('\') + '\'
$sourceCursor=$srcRoot
while($sourceCursor){
    if((Get-Item -LiteralPath $sourceCursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source ancestor is a reparse point.'}
    $sourceCursor=Split-Path -Parent $sourceCursor
}

if ($NoBackup -and $TransactionRoot) {
    throw "-NoBackup cannot be combined with -TransactionRoot."
}

$excludedDirectoryNames = @(
    "__pycache__",
    ".gemini-trash",
    ".sandbox",
    ".sandbox-bin",
    ".sandbox-secrets",
    ".tmp",
    "tmp",
    "plugins",
    "plugin",
    "cache",
    "caches",
    "session",
    "sessions",
    "archived_sessions",
    "log",
    "logs",
    "hook-logs",
    "browser",
    "browser-state",
    "browser_state",
    "computer-use",
    "process_manager",
    "harness-health",
    "harness-changes",
    "harness-learning",
    "harness-state",
    "skills.archived",
    "agents.archived",
    "backups",
    "archived",
    "database",
    "databases",
    "brain",
    "conversations",
    "context_state",
    "crashes",
    "html_artifacts",
    "browser_recordings",
    "implicit",
    "knowledge",
    "prompting",
    "scratch",
    "annotations",
    "bin",
    "sidecar_data",
    "antigravity-browser-profile",
    "antigravity-cli",
    "antigravity-ide",
    "antigravity-backup",
    "builtin"
)
$excludedFileNames = @(
    "auth.json",
    "config.json",
    "config.toml",
    "mcp_config.json",
    ".sync-manifest.json",
    ".gemini-private",
    "installation_id",
    "feishu-bridge-state.json",
    "antigravity_state.pbtxt",
    "skills.txt"
)
$excludedDatabaseExtensions = @(".db", ".db3", ".sdb", ".db-wal", ".db-shm")

function Test-ExcludedSourceFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string[]]$AdditionalExcludedDirectories = @()
    )

    if (($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Source payload contains a reparse-point file: $RelativePath"
    }
    $segments = $RelativePath -split '[\\/]'
    $allExcludedDirectories = @($excludedDirectoryNames) + @($AdditionalExcludedDirectories)
    if (@($segments | Select-Object -First ([math]::Max(0, $segments.Count - 1)) | Where-Object {
        $_ -in $allExcludedDirectories -or $_ -like "backup-*"
    }).Count -gt 0) { return $true }
    if ($File.Name -in $excludedFileNames) { return $true }
    if ($File.Name -eq ".gemini-private" -or $File.Name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$') { return $true }
    if ($File.Name -like "*.sqlite*" -or $File.Extension -in @(".pyc", ".pyo", ".pb", ".pbtxt") + $excludedDatabaseExtensions) { return $true }
    return $false
}

$payloadFiles = New-Object System.Collections.Generic.List[object]
function Add-PayloadFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $source = Join-Path $srcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
    $file = Get-Item -LiteralPath $source -Force
    if (Test-ExcludedSourceFile -File $file -RelativePath $RelativePath) { return }
    $payloadFiles.Add([pscustomobject]@{
        relative_path = $RelativePath
        source_path = $file.FullName
        source_sha256 = Get-FileSha256 -Path $file.FullName
    }) | Out-Null
}

function Add-PayloadDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string[]]$AdditionalExcludedDirectories = @()
    )

    $source = Join-Path $srcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($source)
    $safeFiles=New-Object Collections.Generic.List[object]
    while($queue.Count){
        $directory=$queue.Dequeue()
        if((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source directory is a reparse point.'}
        if(Test-Path -LiteralPath (Join-Path $directory '.gemini-private') -PathType Leaf){continue}
        foreach($child in Get-ChildItem -LiteralPath $directory -Force){
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source contains a reparse point.'}
            if($child.PSIsContainer){if($child.Name -notin $excludedDirectoryNames -and $child.Name -notin $AdditionalExcludedDirectories -and $child.Name -notlike 'backup-*'){$queue.Enqueue($child.FullName)}}
            else {$safeFiles.Add($child)}
        }
    }
    foreach ($file in @($safeFiles.ToArray() | Sort-Object FullName)) {
        $fullRelative = $file.FullName.Substring($srcPrefix.Length)
        if (Test-ExcludedSourceFile -File $file -RelativePath $fullRelative -AdditionalExcludedDirectories $AdditionalExcludedDirectories) { continue }
        $payloadFiles.Add([pscustomobject]@{
            relative_path = $fullRelative
            source_path = $file.FullName
            source_sha256 = Get-FileSha256 -Path $file.FullName
        }) | Out-Null
    }
}

foreach ($file in @("AGENTS.md", "GEMINI.md", "harness.capabilities.json", "harness.components.json")) {
    Add-PayloadFile -RelativePath $file
}
foreach ($directory in @("agents", "skills", "scripts", "templates", "schemas")) {
    Add-PayloadDirectory -RelativePath $directory
}
Add-PayloadDirectory -RelativePath "harness-evals" -AdditionalExcludedDirectories @("runs")

# Both discovery locations are produced from the SAME admitted source file and
# participate in the existing stage, backup, atomic switch, and rollback journal.
# The allowlist expands only to config/skills, never arbitrary config contents.
foreach ($skillFile in @($payloadFiles | Where-Object { $_.relative_path -match '^skills[\\/]' })) {
    $payloadFiles.Add([pscustomobject]@{
        relative_path = 'config\' + [string]$skillFile.relative_path
        source_path = [string]$skillFile.source_path
        source_sha256 = [string]$skillFile.source_sha256
    }) | Out-Null
}

$payloadFiles = @($payloadFiles | Sort-Object relative_path -Unique)
$fingerprintLines = @($payloadFiles | ForEach-Object {
    ([string]$_.relative_path).Replace('\', '/').ToLowerInvariant() + ":" + [string]$_.source_sha256
})
$sourceFingerprint = Get-StringSha256 -Value ($fingerprintLines -join "`n")

$plan = @($payloadFiles | Where-Object { -not (Test-PrivateRuntimeTarget -RelativePath ([string]$_.relative_path)) })
foreach($record in $plan){Assert-PayloadRelativePath ([string]$record.relative_path);Assert-InGeminiHome (Join-Path $GeminiHome ([string]$record.relative_path))}
$copiedCategories = @($plan | ForEach-Object {
    (([string]$_.relative_path) -split '[\\/]')[0]
} | Sort-Object -Unique)

if ($DryRun) {
    [ordered]@{
        status = "dry-run"
        summary = "Runtime sync preview completed."
        gemini_home = $GeminiHome
        source_root = $srcRoot
        copied = $copiedCategories
        planned_file_count = $plan.Count
        source_file_count = $payloadFiles.Count
        source_fingerprint = $sourceFingerprint
        private_targets_preserved = $payloadFiles.Count - $plan.Count
        backup = ""
        transaction_manifest = ""
    } | ConvertTo-Json -Depth 8 -Compress
    return
}

$transaction = $null
$manifestPath = ""
$transactionRootPath = ""
if (-not $NoBackup) {
    foreach($existing in Get-ChildItem -LiteralPath $GeminiHome -Directory -Filter 'backup-*-antigravity-harness-sync') {
        $priorPath=Join-Path $existing.FullName 'sync-transaction.json';Assert-InGeminiHome $priorPath
        if(Test-Path -LiteralPath $priorPath -PathType Leaf){
            $prior=Get-Content -LiteralPath $priorPath -Raw | ConvertFrom-Json
            if([string]$prior.status -notin @('installed','rolled-back')){throw 'Unfinished runtime sync requires explicit rollback before another installation.'}
        }
    }
    if ($TransactionRoot) {
        $transactionRootPath = [System.IO.Path]::GetFullPath($TransactionRoot)
        if (Test-Path -LiteralPath $transactionRootPath) {
            $transactionRootPath = (Resolve-Path -LiteralPath $transactionRootPath).Path
        }
    } else {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $transactionRootPath = Join-Path $GeminiHome ("backup-$stamp-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + "-antigravity-harness-sync")
    }
    $manifestPath = Join-Path $transactionRootPath "sync-transaction.json"
    Assert-TransactionLocation $manifestPath
    if(Test-Path -LiteralPath $transactionRootPath){throw 'Transaction directory must be new.'}
    New-Item -ItemType Directory -Path $transactionRootPath | Out-Null
    if (Test-Path -LiteralPath $manifestPath) {
        throw "Transaction manifest already exists: $manifestPath"
    }

    # Validate an immutable-to-this-operation copy before touching any active runtime file.
    # Optional adapters/desktop-hooks are not part of this plan and are never globally copied.
    $stageRoot=Join-Path $transactionRootPath 'stage'
    foreach($record in $plan) {
        $stagePath=Join-Path $stageRoot ([string]$record.relative_path);Assert-InGeminiHome $stagePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagePath)|Out-Null
        Copy-Item -LiteralPath ([string]$record.source_path) -Destination $stagePath
        if((Get-FileSha256 $stagePath) -cne [string]$record.source_sha256){throw 'Staged source changed while copying; runtime untouched.'}
        if([IO.Path]::GetExtension($stagePath) -eq '.ps1'){
            $tokens=$null;$parseErrors=$null
            [Management.Automation.Language.Parser]::ParseFile($stagePath,[ref]$tokens,[ref]$parseErrors)|Out-Null
            if(@($parseErrors).Count){throw 'Staged PowerShell syntax invalid; runtime untouched.'}
        }
        if([IO.Path]::GetExtension($stagePath) -eq '.json'){Get-Content -LiteralPath $stagePath -Raw | ConvertFrom-Json | Out-Null}
        $record.source_path=$stagePath
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($record in $plan) {
        $relative = [string]$record.relative_path
        $target = Join-Path $GeminiHome $relative
        Assert-InGeminiHome -Path $target
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "Runtime target is a directory, expected a file: $relative"
        }

        $targetExisted = Test-Path -LiteralPath $target -PathType Leaf
        $backupRelative = ""
        $targetHashBefore = ""
        if ($targetExisted) {
            $targetItem = Get-Item -LiteralPath $target -Force
            if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to replace a runtime reparse-point file: $relative"
            }
            $targetHashBefore = Get-FileSha256 -Path $target
            $backupRelative = Join-Path "files" $relative
            $backupPath = Join-Path $transactionRootPath $backupRelative
            Assert-InGeminiHome $backupPath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupPath -Force
            if ((Get-FileSha256 -Path $backupPath) -ne $targetHashBefore) {
                throw "Transaction backup hash mismatch for $relative"
            }
        }

        $createdDirectories = New-Object System.Collections.Generic.List[string]
        $cursor = Split-Path -Parent $target
        while ($cursor -and $cursor -ne $GeminiHome -and -not (Test-Path -LiteralPath $cursor)) {
            $createdDirectories.Add((Get-RelativeRuntimePath -Path $cursor)) | Out-Null
            $next = Split-Path -Parent $cursor
            if (-not $next -or $next -eq $cursor) { break }
            $cursor = $next
        }

        $entries.Add([ordered]@{
            relative_path = $relative
            source_sha256 = [string]$record.source_sha256
            target_existed = [bool]$targetExisted
            target_sha256_before = $targetHashBefore
            backup_relative_path = $backupRelative
            created_directories = $createdDirectories.ToArray()
            state = "prepared"
            target_sha256_after = ""
            rollback_state = "not-needed"
        }) | Out-Null
    }

    $transaction = [ordered]@{
        schema = "antigravity-harness-sync-transaction-v2"
        transaction_id = [guid]::NewGuid().ToString("N")
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        completed_at = $null
        status = "prepared"
        gemini_home_sha256 = $geminiHomeFingerprint
        source_fingerprint = $sourceFingerprint
        source_file_count = $payloadFiles.Count
        planned_file_count = $plan.Count
        files = $entries.ToArray()
        rollback = [ordered]@{
            attempted = $false
            status = "not-needed"
            started_at = $null
            completed_at = $null
            restored_files = 0
            removed_files = 0
            error_sha256 = ""
        }
    }
    Write-JsonAtomically -Path $manifestPath -Value $transaction
}

try {
    if ($transaction) {
        $transaction.status = "installing"
        Write-JsonAtomically -Path $manifestPath -Value $transaction
    }
    $installedCount=0
    foreach ($record in $plan) {
        $relative = [string]$record.relative_path
        $target = Join-Path $GeminiHome $relative
        Assert-InGeminiHome -Path $target
        if(Test-PrivateRuntimeTarget $relative){throw 'Runtime skill/private boundary changed after planning.'}
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        $entry = @($transaction.files | Where-Object { [string]$_.relative_path -eq $relative })[0]
        if($entry.target_existed){if((Get-FileSha256 $target) -cne [string]$entry.target_sha256_before){throw 'Runtime changed after backup.'}}
        elseif(Test-Path -LiteralPath $target){throw 'New runtime target appeared after planning.'}
        if((Get-FileSha256 ([string]$record.source_path)) -cne [string]$record.source_sha256){throw 'Stage changed before switch.'}
        $entry.state='installing';Write-JsonAtomically -Path $manifestPath -Value $transaction
        $switchPath=Join-Path $transactionRootPath ('switch\'+$relative);Assert-InGeminiHome $switchPath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $switchPath)|Out-Null
        Copy-Item -LiteralPath ([string]$record.source_path) -Destination $switchPath
        Assert-InGeminiHome $target
        if($entry.target_existed){
            $oldPath=Join-Path $transactionRootPath ('switch-previous\'+$relative);Assert-InGeminiHome $oldPath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $oldPath)|Out-Null
            [IO.File]::Replace($switchPath,$target,$oldPath)
        } else {[IO.File]::Move($switchPath,$target)}
        $targetHash = Get-FileSha256 -Path $target
        if ($targetHash -ne [string]$record.source_sha256) {
            throw "Installed file hash mismatch for $relative"
        }
        if ($transaction) {
            $entry = @($transaction.files | Where-Object { [string]$_.relative_path -eq $relative })[0]
            $entry.state = "installed"
            $entry.target_sha256_after = $targetHash
            Write-JsonAtomically -Path $manifestPath -Value $transaction
        }
        $installedCount++
        if($TestFailAfterFiles -gt 0 -and $installedCount -eq $TestFailAfterFiles){throw 'Injected isolated runtime install failure.'}
    }
    if ($transaction) {
        foreach($record in $plan){$finalTarget=Join-Path $GeminiHome ([string]$record.relative_path);Assert-InGeminiHome $finalTarget;if((Get-FileSha256 $finalTarget) -cne [string]$record.source_sha256){throw 'Post-install runtime verification failed.'}}
        $transaction.status = "installed"
        $transaction.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        Write-JsonAtomically -Path $manifestPath -Value $transaction
    }
} catch {
    $installError = $_
    if ($transaction) {
        $transaction.status = "install-failed"
        $transaction.install_error_sha256 = Get-StringSha256 -Value $installError.Exception.Message
        Write-JsonAtomically -Path $manifestPath -Value $transaction
        try {
            Invoke-TransactionRollback -Transaction $transaction -ManifestPath $manifestPath | Out-Null
        } catch {
            throw "Runtime sync failed and automatic rollback failed. Transaction: $manifestPath"
        }
        throw "Runtime sync failed and was rolled back. Transaction: $manifestPath"
    }
    throw
}

[ordered]@{
    status = "success"
    summary = "Source payload synced to runtime."
    gemini_home = $GeminiHome
    source_root = $srcRoot
    copied = $copiedCategories
    copied_file_count = $plan.Count
    source_file_count = $payloadFiles.Count
    source_fingerprint = $sourceFingerprint
    private_targets_preserved = $payloadFiles.Count - $plan.Count
    backup = $transactionRootPath
    transaction_manifest = $manifestPath
} | ConvertTo-Json -Depth 8 -Compress
} finally {if($syncLocked){$syncMutex.ReleaseMutex()};$syncMutex.Dispose()}
