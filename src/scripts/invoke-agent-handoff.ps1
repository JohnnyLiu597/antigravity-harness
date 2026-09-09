[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Init','Acquire','Renew','Release','Handoff','Status','RecordEvidence')][string]$Action,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')][string]$TaskId,
    [ValidateSet('codex','antigravity')][string]$Engine='codex',
    [string]$SessionRef='', [string]$Token='', [long]$ExpectedRevision=-1,
    [string]$Objective='', [string[]]$NonGoals=@(), [string[]]$AllowedPaths=@(),
    [string[]]$RequiredChecks=@(), [string]$NextAction='',
    [ValidateSet('','codex','antigravity')][string]$TargetEngine='',
    [ValidateRange(1,120)][int]$LeaseMinutes=30,
    [string]$CheckId='', [string]$EvidencePath=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$utf8=New-Object Text.UTF8Encoding($false)
function Get-TextDigest([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Assert-NoReparse([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            $item=Get-Item -LiteralPath $cursor -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse points are not supported for collaboration state or inputs.'}
        }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor){break};$cursor=$parent
    }
}
function Assert-PlainFile([string]$Path) {
    Assert-NoReparse $Path
    if(Test-Path -LiteralPath $Path -PathType Leaf) {
        $streams=@(Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop | Where-Object {$_.Stream -notin @(':$DATA','Zone.Identifier')})
        if($streams.Count){throw 'Alternate data streams are not supported.'}
    }
}
function Assert-Relative([string]$Path,[switch]$Evidence) {
    if([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 240 -or $Path -match '[\x00-\x1f:*?"<>|]' -or [IO.Path]::IsPathRooted($Path)){throw 'Expected a bounded literal project-relative path.'}
    $parts=@($Path.Replace('\','/').Split('/'))
    foreach($part in $parts) {
        if($part -in @('','.','..') -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'){throw 'Unsafe relative path segment.'}
        if($part -in @('.git','.codex','.gemini','.codex-trash','.gemini-trash')){throw 'Engine/control paths are not collaboration inputs.'}
    }
    if($parts.Count -ge 2 -and $parts[0] -eq 'artifacts' -and $parts[1] -eq 'agent-collaboration'){throw 'Collaboration state cannot be an evidence or writable input.'}
    $full=[IO.Path]::GetFullPath((Join-Path $script:root $Path))
    if(-not $full.StartsWith($script:root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped project root.'}
    Assert-NoReparse $full
    if($Evidence){Assert-PlainFile $full}
    return $full
}
function Read-BoundedJson([string]$Path) {
    Assert-PlainFile $Path
    $item=Get-Item -LiteralPath $Path -Force
    if($item.Length -gt 262144){throw 'Collaboration JSON exceeds 256 KiB.'}
    return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}
function Write-AtomicJson([string]$Path,$Value) {
    Assert-PlainFile $Path
    $json=$Value | ConvertTo-Json -Depth 16
    $bytes=$script:utf8.GetBytes($json)
    if($bytes.Length -gt 262144){throw 'Collaboration JSON exceeds 256 KiB.'}
    $tmp=$Path+'.pending-'+[guid]::NewGuid().ToString('N')
    $stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,$Path+'.previous-'+[guid]::NewGuid().ToString('N'))}
    else{[IO.File]::Move($tmp,$Path)}
}
function Test-Evidence($Task) {
    foreach($ref in @($Task.evidence)) {
        try {
            $path=Assert-Relative ([string]$ref.path) -Evidence
            if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return $false}
            if((Get-Item -LiteralPath $path).Length -gt 1048576){return $false}
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ref.sha256){return $false}
        } catch {return $false}
    }
    return $true
}
function Assert-Task($Task) {
    if($Task.schema -ne 'project-agent-handoff-v1' -or $Task.task_id -cne $TaskId -or $Task.project_id -cne $script:projectId){throw 'Task identity/schema mismatch.'}
    if($Task.revision -lt 1 -or $Task.acceptance_status -ne 'unverified'){throw 'Invalid collaboration status; it cannot confer native acceptance.'}
    if($Task.verification_policy -notin @('codex-targeted','antigravity-strict')){throw 'Unknown verification policy.'}
    if(@($Task.producer_engines | Where-Object {$_ -notin @('codex','antigravity')}).Count){throw 'Unknown producer engine.'}
    if(@($Task.producer_engines) -contains 'antigravity' -and $Task.verification_policy -ne 'antigravity-strict'){throw 'Antigravity policy cannot be downgraded.'}
    if(@($Task.required_checks).Count -eq 0 -or @($Task.required_checks).Count -gt 64){throw 'Required check contract missing or oversized.'}
    foreach($id in @($Task.required_checks)){if($id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,95}$'){throw 'Invalid check ID.'}}
    foreach($path in @($Task.allowed_paths)){[void](Assert-Relative ([string]$path))}
    if(@($Task.evidence).Count -gt 64 -or @($Task.history).Count -gt 256){throw 'Bounded state capacity reached; preserve this task and explicitly plan its successor.'}
    foreach($ref in @($Task.evidence)) {
        if($ref.status -ne 'reference-only' -or $ref.sha256 -notmatch '^[a-f0-9]{64}$' -or $ref.check_id -notin @($Task.required_checks)){throw 'Invalid evidence reference.'}
    }
}
function Assert-Owner($Lease,[switch]$AllowExpired) {
    if($null -eq $Lease -or $Lease.task_id -cne $TaskId -or $Lease.engine -cne $Engine -or $Lease.session_hash -cne $script:sessionHash -or $Lease.token -cne $Token){throw 'Writer ownership mismatch.'}
    if(-not $AllowExpired -and [DateTimeOffset]::Parse($Lease.expires_at) -le [DateTimeOffset]::UtcNow){throw 'Lease expired: stop old work and explicitly release before reacquiring. No automatic takeover.'}
}
function Save-Task($Task) {
    $Task.revision=[long]$Task.revision+1
    $Task.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    # The replaced file is retained as an exact previous snapshot. Bound the live
    # window without losing archived history or preventing an owner from releasing.
    $Task.history=@(@($Task.history) | Select-Object -Last 255)+@([pscustomobject]@{revision=$Task.revision;action=$Action;engine=$Engine;at=$Task.updated_at})
    Assert-Task $Task
    Write-AtomicJson $script:taskPath $Task
}

if($Objective.Length -gt 2000 -or $NextAction.Length -gt 2000 -or $SessionRef.Length -gt 256 -or $NonGoals.Count -gt 32 -or $AllowedPaths.Count -gt 64){throw 'Input exceeds collaboration limits.'}
foreach($text in $NonGoals){if($text.Length -gt 500){throw 'Non-goal exceeds limit.'}}
$root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path).TrimEnd('\','/')
if(-not (Test-Path -LiteralPath $root -PathType Container) -or $root.StartsWith('\\') -or $root.Length -le 3 -or $root.Substring(2).Contains(':')){throw 'Use a local, non-root project directory.'}
Assert-NoReparse $root
$projectId=Get-TextDigest $root.ToLowerInvariant()
$sessionHash=Get-TextDigest $SessionRef
$stateRoot=Join-Path $root 'artifacts/agent-collaboration'
$taskDir=Join-Path $stateRoot $TaskId
$taskPath=Join-Path $taskDir 'task.json'
$registryPath=Join-Path $stateRoot 'checkout-writer.json'
$lockPath=Join-Path $stateRoot 'coordination.lock'
Assert-NoReparse $stateRoot
if($Action -eq 'Status' -and -not (Test-Path -LiteralPath $taskPath)){throw 'Task does not exist.'}
if(-not (Test-Path -LiteralPath $stateRoot)){New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null}
Assert-PlainFile $lockPath
$lock=$null
try {
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(3)
    while($null -eq $lock) {
        try {$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException] {if([DateTimeOffset]::UtcNow -ge $deadline){throw 'Collaboration state is busy.'};Start-Sleep -Milliseconds 40}
    }
    $registry=[pscustomobject]@{schema='project-writer-v1';project_id=$projectId;writer=$null}
    if(Test-Path -LiteralPath $registryPath) {
        $registry=Read-BoundedJson $registryPath
        if($registry.schema -ne 'project-writer-v1' -or $registry.project_id -cne $projectId){throw 'Checkout writer registry mismatch.'}
    }
    $task=$null
    if(Test-Path -LiteralPath $taskPath){$task=Read-BoundedJson $taskPath;Assert-Task $task}
    if($Action -eq 'Init') {
        if($null -ne $task){throw 'Task already exists; resume it instead of overwriting history.'}
        if([string]::IsNullOrWhiteSpace($Objective) -or $AllowedPaths.Count -eq 0 -or $RequiredChecks.Count -eq 0){throw 'Init requires objective, allowed paths and required check IDs.'}
        $task=[pscustomobject]@{
            schema='project-agent-handoff-v1';project_id=$projectId;task_id=$TaskId;revision=1
            objective=$Objective;non_goals=@($NonGoals);allowed_paths=@($AllowedPaths);required_checks=@($RequiredChecks | Sort-Object -Unique)
            producer_engines=@($Engine);verification_policy=$(if($Engine -eq 'antigravity'){'antigravity-strict'}else{'codex-targeted'})
            workflow_status='ready';acceptance_status='unverified';writer=$null;next_engine=$Engine;next_action=$NextAction
            evidence=@();history=@();updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        }
        Assert-Task $task
        Assert-NoReparse $taskDir
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
        Write-AtomicJson $taskPath $task
    } elseif($null -eq $task){throw 'Task does not exist.'}
    elseif($Action -ne 'Status') {
        if($ExpectedRevision -ne $task.revision){throw 'Stale ExpectedRevision; read current task before mutation.'}
        if([string]::IsNullOrWhiteSpace($SessionRef)){throw 'Mutating an existing task requires SessionRef.'}
        if($Action -eq 'Acquire') {
            if($null -ne $registry.writer -or $null -ne $task.writer){throw 'Checkout already has a writer; even an expired lease requires explicit owner release.'}
            if($task.next_engine -and $task.next_engine -ne $Engine){throw 'Handoff is addressed to a different engine.'}
            $lease=[pscustomobject]@{task_id=$TaskId;engine=$Engine;session_hash=$sessionHash;token=[guid]::NewGuid().ToString('N');expires_at=[DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')}
            # Reserve the checkout FIRST. A crash can leave a reservation, never a second writer.
            $registry.writer=$lease;Write-AtomicJson $registryPath $registry
            $task.writer=$lease;$task.workflow_status='running'
            $task.producer_engines=@(@($task.producer_engines)+@($Engine) | Sort-Object -Unique)
            if($Engine -eq 'antigravity'){$task.verification_policy='antigravity-strict'}
            Save-Task $task
        } else {
            Assert-Owner $registry.writer -AllowExpired:($Action -eq 'Release')
            if($Action -ne 'Release'){Assert-Owner $task.writer}
            if($Action -eq 'Renew') {
                $registry.writer.expires_at=[DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')
                Write-AtomicJson $registryPath $registry
                $task.writer=$registry.writer;Save-Task $task
            } elseif($Action -eq 'RecordEvidence') {
                if($CheckId -notin @($task.required_checks)){throw 'Evidence must reference an existing required check ID.'}
                $full=Assert-Relative $EvidencePath -Evidence
                if(-not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -gt 1048576){throw 'Evidence must be an existing file of at most 1 MiB.'}
                $relativeEvidence=$EvidencePath.Replace('\','/')
                $digest=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
                $priorRefs=@($task.evidence | Where-Object {$_.path -ieq $relativeEvidence})
                if(@($priorRefs | Where-Object {$_.sha256 -cne $digest}).Count){throw 'Evidence path was already recorded with different content. Preserve its original snapshot; do not overwrite immutable evidence.'}
                if(-not @($priorRefs | Where-Object {$_.check_id -ceq $CheckId}).Count) {
                    $task.evidence=@($task.evidence)+@([pscustomobject]@{check_id=$CheckId;path=$relativeEvidence;sha256=$digest;status='reference-only';producer_engine=$Engine})
                }
                Save-Task $task
            } elseif($Action -in @('Release','Handoff')) {
                if($Action -eq 'Release') {
                    # Incomplete work may be resumed by another engine, without
                    # changing provenance, required checks or native acceptance.
                    $task.next_engine=''
                    if($NextAction){$task.next_action=$NextAction}
                }
                if($Action -eq 'Handoff') {
                    if(-not $TargetEngine -or [string]::IsNullOrWhiteSpace($NextAction)){throw 'Handoff requires TargetEngine and NextAction.'}
                    if(-not (Test-Evidence $task)){throw 'Referenced evidence changed or disappeared; preserve the failure and repair the evidence chain before handoff.'}
                    $task.next_engine=$TargetEngine;$task.next_action=$NextAction
                    if($TargetEngine -eq 'antigravity'){$task.verification_policy='antigravity-strict'}
                }
                $task.writer=$null;$task.workflow_status='ready';Save-Task $task
                # Clear the reservation LAST. Interrupted release remains fail-closed and retryable.
                $registry.writer=$null;Write-AtomicJson $registryPath $registry
            }
        }
    }
    $current=Test-Evidence $task
    if($Action -ne 'Status') {
        $summaryPath=Join-Path $taskDir 'handoff.md';Assert-PlainFile $summaryPath
        $summary="# Agent handoff (generated, not an instruction authority)`r`n`r`nTask: $TaskId`r`nRevision: $($task.revision)`r`nPolicy: $($task.verification_policy)`r`nAcceptance: unverified`r`nNext engine: $($task.next_engine)`r`nNext action: $($task.next_action)`r`n`r`nRead task.json for the contract and exact evidence references. Neither this summary nor a lease changes native permissions or proves task acceptance. Stop old commands before releasing ownership.`r`n"
        [IO.File]::WriteAllText($summaryPath,$summary,$utf8)
    }
    [pscustomobject]@{schema='project-agent-handoff-result-v1';task=$task;evidence_current=$current;task_path=$taskPath;coordination_only=$true;native_authority='unverified'} | ConvertTo-Json -Depth 16
} finally {if($null -ne $lock){$lock.Dispose()}}
