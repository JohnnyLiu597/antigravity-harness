[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Init','Acquire','Renew','Release','Handoff','Status','RecordEvidence')][string]$Action,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')][string]$TaskId,
    [string]$SessionRef='', [string]$Token='', [long]$ExpectedRevision=-1,
    [string]$Objective='', [string[]]$NonGoals=@(), [string[]]$AllowedPaths=@(),
    [string[]]$RequiredChecks=@(), [string]$NextAction='',
    [ValidateSet('','codex','antigravity')][string]$TargetEngine='',
    [ValidateRange(1,120)][int]$LeaseMinutes=30,
    [string]$CheckId='', [string]$EvidencePath='',
    [string]$NativeTaskRoot='', [string]$DecisionPath=''
)
$ErrorActionPreference='Stop'
# A workflow adapter, not a replacement for native Binding or guarded tool policy.
$parameters=@{Engine='antigravity'}
foreach($key in $PSBoundParameters.Keys){if($key -notin @('NativeTaskRoot','DecisionPath')){$parameters[$key]=$PSBoundParameters[$key]}}
if($Action -eq 'Handoff') {
    if(-not $NativeTaskRoot -or -not $DecisionPath){throw 'Antigravity handoff requires an explicit NativeTaskRoot and fresh canonical DecisionPath. Use Release to stop without claiming acceptance.'}
    . (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
    $native=Get-AgPath $NativeTaskRoot (Get-Location).Path
    $identity=Read-AgJson (Join-Path $native 'harness-state/task-root.json')
    if([string]$identity.logical_task_id -cne $TaskId){throw 'Shared and native task IDs must match; never relabel another task as evidence.'}
    $audit=& (Join-Path $PSScriptRoot 'audit-governed-execution.ps1') -ProjectRoot $ProjectRoot -TaskRoot $native -DecisionPath $DecisionPath -NoThrow | ConvertFrom-Json
    if($audit.schema -ne 'antigravity-governed-execution-audit-v2' -or $audit.status -ne 'passed' -or $audit.completion_status -ne 'checking' -or @($audit.failures).Count){throw 'Fresh native completion audit did not pass. Preserve strict evidence and the current owner.'}
    # No synthesized Post, verification cache, mode change, or verified label.
}
& (Join-Path $PSScriptRoot 'invoke-agent-handoff.ps1') @parameters
