[CmdletBinding()]
param(
    [string]$GeminiHome = "$env:USERPROFILE\.gemini",
    [string]$ProjectRoot = "",
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"

function Assert-ImportSingleLink([string]$Path) {
    if(-not ('AntigravityImport.FileIdentity' -as [type])) {
        Add-Type -TypeDefinition 'using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles; namespace AntigravityImport { public static class FileIdentity { [StructLayout(LayoutKind.Sequential)] struct Info { public uint attr; public System.Runtime.InteropServices.ComTypes.FILETIME c,a,w; public uint vol,hi,lo,links,idxHi,idxLo; } [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i); public static uint Count(string p) { using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) { Info i; if(!GetFileInformationByHandle(f.SafeFileHandle,out i)) throw new IOException("file_identity_unavailable"); return i.links; } } } }' | Out-Null
    }
    if([AntigravityImport.FileIdentity]::Count($Path) -ne 1){throw 'Import refuses hardlinked files.'}
}
function Assert-ImportPath([string]$Path,[string]$Root='') {
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '^\\\\|[\x00-\x1f*?"<>|]' -or $Path.Substring([Math]::Min(2,$Path.Length)).Contains(':')){throw 'Unsupported import path.'}
    foreach($part in ($Path -split '[\\/]')){if($part -notin @('','.','..') -and ($part -match '[. ]$' -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)')){throw 'Ambiguous import path.'}}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if($Root -and $full -ine $Root -and -not $full.StartsWith($Root.TrimEnd('\','/')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Import escaped its declared root.'}
    $cursor=$full
    while($cursor){
        if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Import refuses reparse-point paths.'}}
        $next=Split-Path -Parent $cursor;if($next -eq $cursor){break};$cursor=$next
    }
    if(Test-Path -LiteralPath $full -PathType Leaf){
        Assert-ImportSingleLink $full
        if(@(Get-Item -LiteralPath $full -Stream * | Where-Object {$_.Stream -notin @(':$DATA','Zone.Identifier')}).Count){throw 'Import refuses named alternate data streams.'}
    }
    return $full
}
function Test-ImportPrivate([string]$Path) {
    $cursor=if(Test-Path -LiteralPath $Path -PathType Leaf){Split-Path -Parent $Path}else{$Path}
    while($cursor){
        if(Test-Path -LiteralPath (Join-Path $cursor '.gemini-private')){return $true}
        $next=Split-Path -Parent $cursor;if($next -eq $cursor){break};$cursor=$next
    }
    return $false
}

if (-not $ProjectRoot) {
    $ProjectRoot = Join-Path $PSScriptRoot '..'
}
$ProjectRoot=Assert-ImportPath $ProjectRoot
$GeminiHome=Assert-ImportPath $GeminiHome
if(-not(Test-Path -LiteralPath $ProjectRoot -PathType Container) -or -not(Test-Path -LiteralPath $GeminiHome -PathType Container)){throw 'Import roots must exist as directories.'}
if((Test-ImportPrivate $GeminiHome) -or (Test-ImportPrivate $ProjectRoot)){throw 'Import root is protected by a private marker.'}
$srcRoot = Join-Path $ProjectRoot "src"
$artifactsRoot = Join-Path $ProjectRoot "artifacts"
$null=Assert-ImportPath $srcRoot $ProjectRoot;$null=Assert-ImportPath $artifactsRoot $ProjectRoot
if((Test-ImportPrivate $srcRoot) -or (Test-ImportPrivate $artifactsRoot)){throw 'Import destination is private.'}
if($GeminiHome -ieq $srcRoot -or $GeminiHome.StartsWith($srcRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $srcRoot.StartsWith($GeminiHome+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime and source roots may not overlap.'}
$refreshBackup = ""
$importPlan=New-Object Collections.Generic.List[object]

function Add-ImportFile([string]$Source,[string]$Target) {
    $null=Assert-ImportPath $Source $GeminiHome
    if(Test-ImportPrivate $Source){return}
    $null=Assert-ImportPath $Target $srcRoot
    if(Test-ImportPrivate $Target){throw 'Import would overwrite a private destination.'}
    $importPlan.Add(@{source=$Source;target=$Target;sha256=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash})
}

function Copy-FileIfPresent {
    param([string]$RelativePath)

    $source = Join-Path $GeminiHome $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return $false }
    $target = Join-Path $srcRoot $RelativePath
    Add-ImportFile $source $target
    return $true
}

function Copy-MaintainableDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [string[]]$ExcludeDirectoryNames = @()
    )

    $null=Assert-ImportPath $Source $GeminiHome
    $null=Assert-ImportPath $Target $srcRoot
    if(Test-ImportPrivate $Source){return}
    $sourcePrefix = (Get-Item -LiteralPath $Source).FullName.TrimEnd('\') + '\'
    $excludedDirectories = @($ExcludeDirectoryNames) + @(
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
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($Source)
    $files=New-Object Collections.Generic.List[object]
    while($queue.Count){
        $directory=$queue.Dequeue();$null=Assert-ImportPath $directory $GeminiHome
        if(Test-ImportPrivate $directory){continue}
        foreach($child in Get-ChildItem -LiteralPath $directory -Force){
            if($child.PSIsContainer){
                if($child.Name -in $excludedDirectories -or $child.Name -like 'backup-*'){continue}
                $null=Assert-ImportPath $child.FullName $GeminiHome
                if(-not(Test-ImportPrivate $child.FullName)){$queue.Enqueue($child.FullName)}
            }else{$files.Add($child)}
        }
    }
    foreach ($file in @($files.ToArray())) {
        $relative = $file.FullName.Substring($sourcePrefix.Length)
        $segments = $relative -split '[\\/]'
        if (@($segments | Where-Object { $_ -in $excludedDirectories -or $_ -like "backup-*" }).Count -gt 0) { continue }
        if ($file.Name -in $excludedFileNames) { continue }
        if ($file.Name -eq ".gemini-private" -or $file.Name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$') { continue }
        if ($file.Name -like "*.sqlite*" -or $file.Extension -in @(".pyc", ".pyo", ".pb", ".pbtxt", ".db", ".db3", ".sdb", ".db-wal", ".db-shm")) { continue }
        $destination = Join-Path $Target $relative
        Add-ImportFile $file.FullName $destination
    }
}

function Copy-DirectoryIfPresent {
    param(
        [string]$RelativePath,
        [string[]]$ExcludeDirectoryNames = @()
    )

    $source = Join-Path $GeminiHome $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $false }
    $null=Assert-ImportPath $source $GeminiHome
    if(Test-ImportPrivate $source){return $false}
    $target = Join-Path $srcRoot $RelativePath
    Copy-MaintainableDirectory -Source $source -Target $target -ExcludeDirectoryNames $ExcludeDirectoryNames
    return $true
}

function Test-SkillTreePrivate([string]$Path) {
    if(Test-ImportPrivate $Path){return $true}
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){return $false}
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($Path)
    while($queue.Count){
        $directory=$queue.Dequeue();$null=Assert-ImportPath $directory $GeminiHome
        if(Test-ImportPrivate $directory){return $true}
        foreach($child in Get-ChildItem -LiteralPath $directory -Directory -Force){$null=Assert-ImportPath $child.FullName $GeminiHome;$queue.Enqueue($child.FullName)}
    }
    return $false
}

function Get-SkillImportInventory([string]$Source,[string]$Target) {
    # Build the same safety-filtered plan without changing source files. Drift is
    # rejected before Refresh moves anything, not resolved by picking a timestamp.
    $start=$importPlan.Count
    Copy-MaintainableDirectory -Source $Source -Target $Target
    $entries=@($importPlan.GetRange($start,$importPlan.Count-$start).ToArray())
    $importPlan.RemoveRange($start,$importPlan.Count-$start)
    return $entries
}

function Copy-ActiveSkills {
    $canonical = Join-Path $GeminiHome 'config\skills'
    $legacy = Join-Path $GeminiHome 'skills'
    foreach($skillRoot in @($canonical,$legacy)){$null=Assert-ImportPath $skillRoot $GeminiHome}
    if((Test-ImportPrivate $canonical) -or (Test-ImportPrivate $legacy)){return 0}
    $target = Join-Path $srcRoot "skills"
    $null=Assert-ImportPath $target $srcRoot
    $names=@(foreach($skillRoot in @($canonical,$legacy)){
        if(Test-Path -LiteralPath $skillRoot -PathType Container){Get-ChildItem -LiteralPath $skillRoot -Directory -Force | Select-Object -ExpandProperty Name}
    }) | Sort-Object -Unique
    $count = 0
    foreach ($name in $names) {
        if ($name -in @('.system','builtin')) { continue }
        $modernSkill=Join-Path $canonical $name;$legacySkill=Join-Path $legacy $name
        if((Test-SkillTreePrivate $modernSkill) -or (Test-SkillTreePrivate $legacySkill)){continue}
        $destination=Join-Path $target $name
        $modernEntries=@();$legacyEntries=@()
        $hasModern=Test-Path -LiteralPath $modernSkill -PathType Container
        $hasLegacy=Test-Path -LiteralPath $legacySkill -PathType Container
        if($hasModern){$modernEntries=@(Get-SkillImportInventory $modernSkill $destination)}
        if($hasLegacy){$legacyEntries=@(Get-SkillImportInventory $legacySkill $destination)}
        if($hasModern -and $hasLegacy){
            $modernFacts=@($modernEntries | ForEach-Object { $_.target.ToLowerInvariant()+'|'+$_.sha256 } | Sort-Object)
            $legacyFacts=@($legacyEntries | ForEach-Object { $_.target.ToLowerInvariant()+'|'+$_.sha256 } | Sort-Object)
            if(($modernFacts -join "`n") -cne ($legacyFacts -join "`n")){throw 'Canonical and legacy skill copies differ; resolve drift explicitly before import.'}
        }
        $selected=if($hasModern){$modernEntries}else{$legacyEntries}
        foreach($entry in @($selected)){
            if($hasModern -and $hasLegacy){
                $peer=@($legacyEntries | Where-Object {$_.target -ieq $entry.target})[0]
                $entry.skill_counterpart=$peer.source
                $entry.skill_counterpart_sha256=$peer.sha256
            }
            $importPlan.Add($entry)
        }
        $count++
    }
    return $count
}

$copiedFiles = New-Object System.Collections.Generic.List[string]
foreach ($file in @("AGENTS.md", "GEMINI.md", "harness.capabilities.json", "harness.components.json")) {
    if (Copy-FileIfPresent -RelativePath $file) { $copiedFiles.Add($file) | Out-Null }
}

$copiedDirs = New-Object System.Collections.Generic.List[string]
foreach ($dir in @("agents", "scripts", "templates", "schemas")) {
    if (Copy-DirectoryIfPresent -RelativePath $dir) { $copiedDirs.Add($dir) | Out-Null }
}
if (Copy-DirectoryIfPresent -RelativePath "harness-evals" -ExcludeDirectoryNames @("runs")) {
    $copiedDirs.Add("harness-evals") | Out-Null
}

$skillCount = Copy-ActiveSkills

# Finish admission for the whole plan before Refresh moves any existing source.
# This is bounded preflight, not a fully transactional import or an OS boundary.
$manifestDirectory = Join-Path $artifactsRoot 'sync-manifests'
$null=Assert-ImportPath $manifestDirectory $artifactsRoot
if(Test-ImportPrivate $manifestDirectory){throw 'Import manifest destination is private.'}
if($Refresh -and (Test-Path -LiteralPath $srcRoot)){
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($srcRoot)
    while($queue.Count){
        $dir=$queue.Dequeue();$null=Assert-ImportPath $dir $srcRoot
        if(Test-ImportPrivate $dir){throw 'Refresh refuses to move private source directories.'}
        foreach($item in Get-ChildItem -LiteralPath $dir -Force){$null=Assert-ImportPath $item.FullName $srcRoot;if($item.PSIsContainer){$queue.Enqueue($item.FullName)}}
    }
}
New-Item -ItemType Directory -Force -Path $srcRoot,$artifactsRoot | Out-Null
if($Refresh){
    $backup=Join-Path $artifactsRoot ('sync-refresh-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
    $null=Assert-ImportPath $backup $artifactsRoot
    New-Item -ItemType Directory -Path $backup|Out-Null;$refreshBackup=$backup
    foreach($item in Get-ChildItem -LiteralPath $srcRoot -Force){
        $null=Assert-ImportPath $item.FullName $srcRoot;$null=Assert-ImportPath $backup $artifactsRoot
        Move-Item -LiteralPath $item.FullName -Destination $backup
    }
}
foreach($entry in $importPlan){
    $null=Assert-ImportPath $entry.source $GeminiHome;$null=Assert-ImportPath $entry.target $srcRoot
    if((Test-ImportPrivate $entry.source) -or (Test-ImportPrivate $entry.target)){throw 'Private marker changed during import.'}
    if((Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash -cne $entry.sha256){throw 'Runtime source changed during import.'}
    if($entry.ContainsKey('skill_counterpart')){
        $null=Assert-ImportPath $entry.skill_counterpart $GeminiHome
        if((Test-ImportPrivate $entry.skill_counterpart) -or (Get-FileHash -LiteralPath $entry.skill_counterpart -Algorithm SHA256).Hash -cne $entry.skill_counterpart_sha256){throw 'Canonical/legacy counterpart changed during import.'}
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.target)|Out-Null
    $null=Assert-ImportPath $entry.target $srcRoot
    Copy-Item -LiteralPath $entry.source -Destination $entry.target -Force
    if((Get-FileHash -LiteralPath $entry.target -Algorithm SHA256).Hash -cne $entry.sha256){throw 'Imported file hash mismatch.'}
}

$manifest = [ordered]@{
    schema = "antigravity-harness-source-sync-v1"
    synced_at = (Get-Date).ToString("o")
    direction = "runtime-to-source"
    gemini_home = $GeminiHome
    project_root = $ProjectRoot
    copied_files = $copiedFiles.ToArray()
    copied_directories = $copiedDirs.ToArray()
    copied_skill_count = $skillCount
}

$null=Assert-ImportPath $manifestDirectory $artifactsRoot
New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null
$manifestPath = Join-Path $manifestDirectory ((Get-Date -Format "yyyyMMdd-HHmmssfff") + '-' + [guid]::NewGuid().ToString('N') + "-runtime-to-source.json")
$null=Assert-ImportPath $manifestPath $artifactsRoot
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

[ordered]@{
    status = "success"
    summary = "Runtime source payload imported."
    gemini_home = $GeminiHome
    source_root = $srcRoot
    copied_files = $copiedFiles.ToArray()
    copied_directories = $copiedDirs.ToArray()
    copied_skill_count = $skillCount
    manifest = $manifestPath
    refresh_backup = $refreshBackup
    recovery_limit = 'Preflight and per-file checks, not a transactional import. Refresh backups and partial outputs remain retained on failure.'
} | ConvertTo-Json -Depth 8 -Compress
