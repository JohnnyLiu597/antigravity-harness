[CmdletBinding()]
param(
    [string]$ProjectRoot = "", [string]$SourceRoot = "", [string]$TargetRoot = "",
    [ValidateSet('Install','Diagnose','Enable','Disable','Rollback')][string]$Mode = 'Install',
    [switch]$DryRun, [string]$RollbackManifest = "",
    [ValidateSet('','AfterStage','AfterBackup','AfterSwitch','CrashAfterBackup')][string]$TestFailurePoint = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$pluginName = 'antigravity-reliable-control'
function Full([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^\\\\|[\x00-\x1f]|[<>"|?*])' -or $Path.Substring([Math]::Min(2,$Path.Length)).Contains(':')) { throw 'Unsafe local path.' }
    $fullPath=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    foreach ($part in ($fullPath.Substring([IO.Path]::GetPathRoot($fullPath).Length) -split '[\\/]')) {
        if ($part -match '[. ]$|^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)' ) { throw 'Ambiguous Windows path component.' }
    }
    return $fullPath
}
function NoLinks([string]$Path) {
    $cursor=Full $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point paths are not admitted.' }
        }
        $parent=Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }; $cursor=$parent
    }
}
function Files([string]$Root) {
    NoLinks $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw 'Plugin directory missing.' }
    $queue=New-Object 'Collections.Generic.Queue[string]'; $queue.Enqueue($Root)
    $items=New-Object Collections.Generic.List[object]
    while ($queue.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Plugin contains a reparse point.' }
            [void](Full $item.FullName)
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) } else {
                if (@(Get-Item -LiteralPath $item.FullName -Stream * | Where-Object {$_.Stream -notin @(':$DATA','Zone.Identifier')}).Count) { throw 'Plugin contains alternate data streams.' }
                $items.Add($item)
            }
            if ($items.Count -gt 512 -or $queue.Count -gt 128) { throw 'Plugin exceeds bounded file count.' }
        }
    }
    return @($items.ToArray() | Sort-Object FullName)
}
function Snapshot([string]$Root) {
    $prefix=(Full $Root)+'\'
    return @(Files $Root | ForEach-Object { [ordered]@{relative_path=$_.FullName.Substring($prefix.Length).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
}
function AssertSnapshot([string]$Root, $Expected) {
    $actual=@(Snapshot $Root); $want=@($Expected)
    if ($actual.Count -ne $want.Count -or $want.Count -eq 0) { throw 'Plugin file set mismatch.' }
    $seen=@{}
    foreach ($entry in $want) {
        $rel=[string]$entry.relative_path
        if ($rel -notmatch '^[a-zA-Z0-9_. /-]+$' -or $rel -match '(^/|(^|/)\.\.?(/|$))' -or $seen.ContainsKey($rel) -or [string]$entry.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid snapshot entry.' }
        $seen[$rel]=[string]$entry.sha256
    }
    foreach ($entry in $actual) { if (-not $seen.ContainsKey($entry.relative_path) -or $seen[$entry.relative_path] -cne $entry.sha256) { throw 'Plugin content hash mismatch.' } }
}
function ValidatePlugin([string]$Root) {
    $items=@(Files $Root)
    if ($items.Count -eq 0 -or ($items | Measure-Object -Property Length -Sum).Sum -gt 16777216) { throw 'Plugin is empty or exceeds 16 MiB.' }
    $plugin=Get-Content -LiteralPath (Join-Path $Root 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($plugin.name -cne $pluginName) { throw 'Unexpected plugin identity.' }
    $hooks=Get-Content -LiteralPath (Join-Path $Root 'hooks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($hooks.PSObject.Properties).Count -ne 1 -or -not $hooks.PSObject.Properties['antigravity-reliable-control-probe']) { throw 'Unexpected hooks owner.' }
    $definition=$hooks.'antigravity-reliable-control-probe'
    if ($definition.enabled -isnot [bool]) { throw 'Hook enabled flag must be boolean.' }
    foreach ($event in @('PreToolUse','PostToolUse')) { if (-not $definition.PSObject.Properties[$event]) { throw 'Required lifecycle hook missing.' } }
    foreach ($property in $definition.PSObject.Properties) {
        if ($property.Name -eq 'enabled') { continue }
        if ($property.Name -notin @('PreToolUse','PostToolUse','Stop')) { throw 'Unsupported lifecycle hook.' }
        foreach ($group in @($property.Value)) {
            foreach ($hook in @($group.hooks)) {
                if ($hook.type -cne 'command' -or [string]$hook.command -notmatch '^hooks\\[a-z0-9-]+\.cmd$' -or $hook.timeout -le 0 -or $hook.timeout -gt 30) { throw 'Hook command must be a bounded plugin-relative wrapper.' }
                if (-not (Test-Path -LiteralPath (Join-Path $Root $hook.command) -PathType Leaf)) { throw 'Hook command is missing.' }
            }
        }
    }
    foreach ($file in $items) {
        if ($file.Extension -eq '.json') { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
        if ($file.Extension -eq '.ps1') {
            $tokens=$null; $parseErrors=$null
            [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
            if (@($parseErrors).Count) { throw 'Plugin PowerShell syntax invalid.' }
        }
    }
}
function SaveJournal([string]$Path,$Value) {
    NoLinks $Path
    $pending=$Path+'.'+[guid]::NewGuid().ToString('N')+'.pending'
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Value | ConvertTo-Json -Depth 20))
    $stream=[IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($pending,$Path,($Path+'.'+[guid]::NewGuid().ToString('N')+'.superseded')) } else { [IO.File]::Move($pending,$Path) }
}
function CopyTree([string]$From,[string]$To) {
    NoLinks $From; NoLinks $To
    if (Test-Path -LiteralPath $To) { throw 'Staging destination must not exist.' }
    New-Item -ItemType Directory -Path $To | Out-Null
    foreach ($file in @(Files $From)) {
        $relative=$file.FullName.Substring((Full $From).Length+1)
        $dest=Join-Path $To $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        NoLinks $file.FullName; NoLinks $dest
        Copy-Item -LiteralPath $file.FullName -Destination $dest
    }
}
function MoveTree([string]$From,[string]$To) {
    NoLinks $From; NoLinks $To
    if (-not (Test-Path -LiteralPath $From -PathType Container) -or (Test-Path -LiteralPath $To)) { throw 'Unsafe switch state.' }
    [IO.Directory]::Move($From,$To)
}
function ReadJournal([string]$Path) {
    $pathFull=Full $Path; NoLinks $pathFull
    $folder=Split-Path -Parent $pathFull
    if ((Split-Path -Parent $folder) -ine $historyRoot -or (Split-Path -Leaf $folder) -notmatch '^[a-f0-9]{32}$' -or (Split-Path -Leaf $pathFull) -cne 'install-transaction.json') { throw 'Manifest is outside this plugin transaction store.' }
    $value=Get-Content -LiteralPath $pathFull -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($value.schema -cne 'antigravity-desktop-hook-install-v2' -or $value.transaction_id -cne (Split-Path -Leaf $folder) -or (Full $value.target_root) -ine $TargetRoot -or (Full $value.backup_root) -ine (Join-Path $folder 'previous') -or (Full $value.stage_root) -ine (Join-Path $folder 'stage') -or $value.target_existed -isnot [bool]) { throw 'Manifest boundary or identity mismatch.' }
    if ($value.status -notin @('staging','validated','switching','installed','failed-recovered','recovery-required','rolling-back','rolled-back')) { throw 'Unknown transaction status.' }
    return $value
}
function PendingTransactions {
    $pending=@()
    if (Test-Path -LiteralPath $historyRoot) {
        foreach ($dir in Get-ChildItem -LiteralPath $historyRoot -Directory -Force) {
            NoLinks $dir.FullName
            if ($dir.Name -notmatch '^[a-f0-9]{32}$') { throw 'Unexpected transaction directory.' }
            $path=Join-Path $dir.FullName 'install-transaction.json'
            if (-not (Test-Path -LiteralPath $path)) { throw 'Transaction directory has no durable journal.' }
            $m=ReadJournal $path
            if ($m.status -notin @('installed','failed-recovered','rolled-back')) { $pending+=$path }
        }
    }
    return $pending
}
if (-not $ProjectRoot) { $ProjectRoot=Full (Join-Path $PSScriptRoot '..') }
if (-not $SourceRoot) { $SourceRoot=Join-Path $ProjectRoot 'src\desktop-hooks\antigravity-reliable-control' }
if (-not $TargetRoot) { if (-not $env:USERPROFILE) { throw 'TargetRoot required.' }; $TargetRoot=Join-Path $env:USERPROFILE '.gemini\config\plugins\antigravity-reliable-control' }
$TargetRoot=Full $TargetRoot; NoLinks $TargetRoot
$SourceRoot=Full $SourceRoot
$pluginsRoot=Split-Path -Parent $TargetRoot; $configRoot=Split-Path -Parent $pluginsRoot
$tempRoot=Full ([IO.Path]::GetTempPath())
$isTestTarget=((Split-Path -Leaf $TargetRoot) -ceq $pluginName -and (Split-Path -Leaf $pluginsRoot) -ceq 'plugins' -and (Split-Path -Parent $configRoot) -ieq $tempRoot -and (Split-Path -Leaf $configRoot) -match '^antigravity-[a-z0-9-]+-[a-f0-9]{32}$')
$productionTarget=if($env:USERPROFILE){Full (Join-Path $env:USERPROFILE '.gemini\config\plugins\antigravity-reliable-control')}else{''}
if ($TargetRoot -ine $productionTarget -and -not $isTestTarget) { throw 'Target must be the named desktop plugin or an isolated antigravity-* GUID TEMP fixture/plugins directory.' }
if ($TestFailurePoint -and -not $isTestTarget) { throw 'Failure injection is restricted to isolated TEMP fixtures.' }
$historyRoot=Join-Path $configRoot 'plugin-backups\antigravity-reliable-control'; NoLinks $historyRoot
$lockPath=Join-Path $historyRoot 'install.lock'; NoLinks $lockPath
if ($RollbackManifest) { $Mode='Rollback' }
if ($Mode -eq 'Rollback' -and -not $RollbackManifest) { throw 'Rollback requires an explicit transaction manifest.' }
if ($Mode -eq 'Diagnose') {
    $busy=$false
    if (Test-Path -LiteralPath $lockPath) { try { $probe=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None); $probe.Dispose() } catch { $busy=$true } }
    if ($busy) { [ordered]@{status='busy';live_desktop_verified=$false;pending_transactions=@()} | ConvertTo-Json -Compress; return }
    try {
        $pending=@(PendingTransactions)
        $health=if($pending.Count){'recovery-required'}elseif(-not(Test-Path -LiteralPath $TargetRoot)){'not-installed'}else{ValidatePlugin $TargetRoot; 'healthy'}
        [ordered]@{status=$health;target_root=$TargetRoot;pending_transactions=$pending;live_desktop_verified=$false} | ConvertTo-Json -Compress
    } catch { [ordered]@{status='invalid';reason='Plugin or transaction integrity invalid; inspect retained local artifacts.';live_desktop_verified=$false;pending_transactions=@()} | ConvertTo-Json -Compress }
    return
}
if ($DryRun) {
    if ($Mode -eq 'Rollback') { $m=ReadJournal $RollbackManifest; if($m.target_existed){AssertSnapshot $m.backup_root $m.previous_files} }
    elseif ($Mode -eq 'Install') { ValidatePlugin $SourceRoot }
    else { ValidatePlugin $TargetRoot }
    [ordered]@{status='dry-run';action=$Mode.ToLowerInvariant();target_root=$TargetRoot;live_desktop_verified=$false} | ConvertTo-Json -Compress; return
}
New-Item -ItemType Directory -Force -Path $historyRoot | Out-Null
NoLinks $historyRoot; NoLinks $lockPath
try { $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch { throw 'Plugin deployment busy; no changes made.' }
try {
    NoLinks $TargetRoot
    if ($Mode -eq 'Rollback') {
        $manifestPath=Full $RollbackManifest; $m=ReadJournal $manifestPath
        if ($m.status -eq 'rolled-back') { [ordered]@{status='rolled-back';idempotent=$true;transaction_manifest=$manifestPath} | ConvertTo-Json -Compress; return }
        if ($m.status -eq 'failed-recovered') { throw 'Failed transaction already recovered; no rollback needed.' }
        $folder=Split-Path -Parent $manifestPath
        $hasPrevious=Test-Path -LiteralPath $m.backup_root -PathType Container
        if ($m.target_existed -and $hasPrevious) { AssertSnapshot $m.backup_root $m.previous_files }
        if ($m.target_existed -and -not $hasPrevious) { AssertSnapshot $TargetRoot $m.previous_files }
        elseif (Test-Path -LiteralPath $TargetRoot) {
            AssertSnapshot $TargetRoot $m.files
            $m.status='rolling-back'; SaveJournal $manifestPath $m
            MoveTree $TargetRoot (Join-Path $folder ('displaced-'+[guid]::NewGuid().ToString('N')))
        }
        if ($m.target_existed -and $hasPrevious) { MoveTree $m.backup_root $TargetRoot; AssertSnapshot $TargetRoot $m.previous_files }
        $m.status='rolled-back'; SaveJournal $manifestPath $m
        [ordered]@{status='rolled-back';target_root=$TargetRoot;transaction_manifest=$manifestPath;live_desktop_verified=$false} | ConvertTo-Json -Compress; return
    }
    $pending=@(PendingTransactions)
    if ($pending.Count) { throw 'Interrupted transaction requires Diagnose and explicit Rollback before another install.' }
    $targetExisted=Test-Path -LiteralPath $TargetRoot -PathType Container
    if ((Test-Path -LiteralPath $TargetRoot) -and -not $targetExisted) { throw 'Plugin target is not a directory.' }
    if ($targetExisted) { ValidatePlugin $TargetRoot }
    if ($Mode -in @('Enable','Disable') -and -not $targetExisted) { throw 'Plugin not installed.' }
    $candidate=if($Mode -eq 'Install'){$SourceRoot}else{$TargetRoot}
    ValidatePlugin $candidate
    $expected=@(Snapshot $candidate); $previous=if($targetExisted){@(Snapshot $TargetRoot)}else{@()}
    $id=[guid]::NewGuid().ToString('N'); $folder=Join-Path $historyRoot $id
    New-Item -ItemType Directory -Path $folder | Out-Null
    $manifestPath=Join-Path $folder 'install-transaction.json'
    $m=[ordered]@{schema='antigravity-desktop-hook-install-v2';transaction_id=$id;created_at=[DateTime]::UtcNow.ToString('o');action=$Mode.ToLowerInvariant();status='staging';target_root=$TargetRoot;target_existed=$targetExisted;backup_root=(Join-Path $folder 'previous');stage_root=(Join-Path $folder 'stage');files=$expected;previous_files=@($previous);live_desktop_verified=$false}
    SaveJournal $manifestPath $m
    try {
        CopyTree $candidate $m.stage_root
        AssertSnapshot $m.stage_root $expected
        if ($Mode -in @('Enable','Disable')) {
            $hooksPath=Join-Path $m.stage_root 'hooks.json'; $hooks=Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $hooks.'antigravity-reliable-control-probe'.enabled=($Mode -eq 'Enable')
            # Staging is not active. Preserve the old hooks document in the transaction,
            # not as an extra executable/discoverable file in the installed payload.
            Copy-Item -LiteralPath $hooksPath -Destination (Join-Path $folder 'previous-hooks.json')
            [IO.File]::WriteAllText($hooksPath,($hooks | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
            $m.files=@(Snapshot $m.stage_root)
        }
        ValidatePlugin $m.stage_root; AssertSnapshot $m.stage_root $m.files
        $m.status='validated'; SaveJournal $manifestPath $m
        if ($TestFailurePoint -eq 'AfterStage') { throw 'Injected stage failure.' }
        if ($targetExisted) { AssertSnapshot $TargetRoot $m.previous_files }
        $m.status='switching'; SaveJournal $manifestPath $m
        New-Item -ItemType Directory -Force -Path $pluginsRoot | Out-Null; NoLinks $pluginsRoot
        if ($targetExisted) { MoveTree $TargetRoot $m.backup_root }
        if ($TestFailurePoint -in @('AfterBackup','CrashAfterBackup')) { throw 'Injected switch interruption.' }
        MoveTree $m.stage_root $TargetRoot
        if ($TestFailurePoint -eq 'AfterSwitch') { throw 'Injected post-install failure.' }
        ValidatePlugin $TargetRoot; AssertSnapshot $TargetRoot $m.files
        $m.status='installed'; SaveJournal $manifestPath $m
    } catch {
        if ($TestFailurePoint -eq 'CrashAfterBackup') { throw 'Simulated process interruption; explicit rollback required.' }
        try {
            $hasPrevious=Test-Path -LiteralPath $m.backup_root -PathType Container
            if ($hasPrevious) {
                AssertSnapshot $m.backup_root $m.previous_files
                if (Test-Path -LiteralPath $TargetRoot) { MoveTree $TargetRoot (Join-Path $folder 'failed-candidate') }
                MoveTree $m.backup_root $TargetRoot; AssertSnapshot $TargetRoot $m.previous_files
            } elseif (-not $targetExisted -and (Test-Path -LiteralPath $TargetRoot)) { MoveTree $TargetRoot (Join-Path $folder 'failed-candidate') }
            elseif ($targetExisted) { AssertSnapshot $TargetRoot $m.previous_files }
            $m.status='failed-recovered'; SaveJournal $manifestPath $m
        } catch { $m.status='recovery-required'; SaveJournal $manifestPath $m; throw "Deployment recovery required. Transaction: $manifestPath" }
        throw "Deployment failed; previous state recovered; artifacts retained. Transaction: $manifestPath"
    }
    [ordered]@{status=if($Mode -eq 'Install'){'installed'}else{$Mode.ToLowerInvariant()};target_root=$TargetRoot;file_count=@($m.files).Count;hash_mismatches=0;backup=if($targetExisted){$m.backup_root}else{$null};transaction_manifest=$manifestPath;live_desktop_verified=$false} | ConvertTo-Json -Compress
} finally { $lock.Dispose() }
