param([Parameter(Mandatory=$true)][string]$StatePath,[Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$TaskId,[ValidateSet('checking','unverified','blocked')][string]$DecisionStatus='unverified',[switch]$UserCancelled,[switch]$EmergencyDisabled)
$ErrorActionPreference='Stop'
# Local evaluator only. Cancellation/disable precede dependency and state access.
if($UserCancelled -or $EmergencyDisabled){[ordered]@{action='stop';status=if($EmergencyDisabled){'disabled'}else{'cancelled'};retry_count=0;host_activation='unverified'}|ConvertTo-Json -Compress;return}
try{
 . (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
 Set-StrictMode -Off
 $full=Get-AgPath $StatePath (Get-Location).Path
 Invoke-AgLock ($full+'.lock') {
  $count=0
  if(Test-Path -LiteralPath $full){
   $null=Get-AgPath $full
   $prior=Read-AgJson $full
   if($prior.schema -ne 'antigravity-bounded-stop-v1' -or $prior.task_id -ne $TaskId -or $prior.retry_count -isnot [int] -or [int]$prior.retry_count -lt 0 -or [int]$prior.retry_count -gt 2){throw 'state invalid'}
   $count=[int]$prior.retry_count
  }
  $action='stop';$status=$DecisionStatus
  if($DecisionStatus -ne 'checking'){if($count -lt 2){$count++;$action='request-check';$status='checking'}else{$status='blocked'}}
  $record=[ordered]@{schema='antigravity-bounded-stop-v1';task_id=$TaskId;retry_count=$count;action=$action;status=$status;host_activation='unverified';updated_at=[DateTime]::UtcNow.ToString('o')}
  Write-AgAtomic $full $record
  $record|ConvertTo-Json -Compress
 }
}catch{[ordered]@{action='stop';status='blocked';retry_count=2;reason='state-unavailable';host_activation='unverified'}|ConvertTo-Json -Compress}
