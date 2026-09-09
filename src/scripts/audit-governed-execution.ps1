param([string]$ProjectRoot='.',[Parameter(Mandatory=$true)][string]$TaskRoot,[string]$DecisionPath='',[switch]$NoThrow)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
Set-StrictMode -Off
$failures=New-Object 'System.Collections.Generic.List[string]'
function Fail([string]$code){if(-not $failures.Contains($code)){$failures.Add($code)|Out-Null}}
$task=(Get-Item -LiteralPath (Resolve-Path -LiteralPath $TaskRoot).Path -Force).FullName
function Inside([string]$p){$v=Get-AgPath $p $task;if(-not $v.StartsWith($task.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'outside'};$v}
if(-not $DecisionPath){Fail 'decision-reference-required'}else{
 try{
  $selected=Inside $DecisionPath
  $decision=Get-Content -LiteralPath $selected -Raw -Encoding UTF8|ConvertFrom-Json
  if($decision.schema -ne 'antigravity-completion-decision-v1' -or $decision.status -ne 'checking' -or @($decision.failures).Count){Fail 'decision-invalid'}
  $claimPath=Inside ([string]$decision.claim.path)
  if((Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $decision.claim.sha256){Fail 'claim-reference-hash-mismatch'}
  $fresh=& (Join-Path $PSScriptRoot 'invoke-completion-gate.ps1') -ProjectRoot $task -ClaimPath $claimPath -ReadOnly|ConvertFrom-Json
  foreach($code in @($fresh.failures)){Fail ([string]$code)}
  if($fresh.envelope.sha256 -ne $decision.envelope.sha256){Fail 'decision-envelope-mismatch'}
  $manifestPath=Join-Path $task 'harness-state/task-root.json'
  if(Test-Path -LiteralPath $manifestPath){$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json;if($manifest.logical_task_id -ne $fresh.task_id){Fail 'task-root-identity-mismatch'}}else{Fail 'task-root-manifest-missing'}
 }catch{Fail 'explicit-chain-invalid'}
}
$r=[ordered]@{schema='antigravity-governed-execution-audit-v2';status=if($failures.Count){'failed'}else{'passed'};authority_status='unverified';completion_status=if($failures.Count){'unverified'}else{'checking'};read_only=$true;failures=$failures.ToArray()}
$json=$r|ConvertTo-Json -Compress
if($failures.Count -and -not $NoThrow){$json|Out-Host;throw 'Governed execution audit failed.'}
$json
