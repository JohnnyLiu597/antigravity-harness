param(
 [string]$StateRoot='',
 [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ConversationId,
 [string]$TaskRoot='', [string]$ContractPath='', [string]$LedgerPath='', [string]$AttemptId='',
 [ValidateSet('maker','test-author','test-runner','reviewer','human')][string]$Role='maker',
 [ValidateSet('Create','Renew','Revoke')][string]$Action='Create',
 [ValidateRange(1,1440)][int]$ExpiresInMinutes=60,
 [string[]]$AllowedPaths=@(), [int]$ExpectedRevision=0
)
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
try {
 if(-not $StateRoot){$StateRoot=(Get-AgRoots).bindings}
 $state=Get-AgPath $StateRoot;$hash=Get-AgHash $ConversationId;$path=Join-Path $state ('sessions\'+$hash+'.json')
 $result=Invoke-AgLock ($path+'.lock') {
  $previous=if(Test-Path -LiteralPath $path){Read-AgJson $path}else{$null}
  if($Action -eq 'Create' -and $previous){throw 'binding_exists'}
  if($Action -ne 'Create' -and -not $previous){throw 'binding_missing'}
  if($previous -and $ExpectedRevision -gt 0 -and $previous.revision -ne $ExpectedRevision){throw 'revision_conflict'}
  if($Action -eq 'Revoke'){
   $previous.status='revoked';$previous.revision=[int]$previous.revision+1;Write-AgAtomic $path $previous
   return @{status='success';binding=$path;revision=$previous.revision;binding_status='revoked'}
  }
  if($previous){
   if($previous.status -eq 'revoked'){throw 'revoked_binding_cannot_renew'}
   if(-not $TaskRoot){$TaskRoot=$previous.task_root};if(-not $ContractPath){$ContractPath=$previous.contract_path};if(-not $LedgerPath){$LedgerPath=$previous.ledger_path};if(-not $AttemptId){$AttemptId=$previous.attempt_id}
   if($Role -ne $previous.role){throw 'renew_cannot_change_role'}
  }
  $task=Get-AgPath $TaskRoot;$cp=Get-AgPath $ContractPath;$lp=Get-AgPath $LedgerPath
  if(-not(Test-AgWithin $cp $task) -or -not(Test-AgWithin $lp $task)){throw 'governance_outside_task'}
  $c=Read-AgJson $cp;$l=Read-AgJson $lp
  if($c.schema -ne 'antigravity-harness-task-contract-v2' -or $l.schema -ne 'antigravity-harness-attempt-ledger-v1'){throw 'schema_mismatch'}
  if($Role -in @('maker','test-author') -and ([string](Get-AgField $c.scope 'access' '') -ne 'write' -or [string](Get-AgField $c 'status' '') -ne 'draft')){throw 'contract_not_writable'}
  if((Get-AgPath $c.scope.project_root) -ne $task -or (Get-AgPath $l.project_root) -ne $task -or $c.contract_id -ne $l.task_id){throw 'task_identity'}
  $a=@($l.attempts|Where-Object attempt_id -eq $AttemptId);if($a.Count -ne 1 -or $a[0].status -ne 'running'){throw 'attempt_not_running'}
  $ar=[string](Get-AgField $a[0] 'role' '');if($ar -and $ar -ne $Role){throw 'role_conflict'}
  if($AllowedPaths.Count -eq 0){$AllowedPaths=if($previous){@($previous.allowed_paths)}else{@($c.scope.allowed_paths)}}
  foreach($rule in $AllowedPaths){if(-not @($c.scope.allowed_paths|Where-Object {Test-AgRule $rule ([string]$_)}).Count){throw 'scope_expansion'}}
  if($previous){
   if($previous.task_root -ne $task -or $previous.logical_task_id_sha256 -ne (Get-AgHash ([string]$l.task_id)) -or $previous.contract_file_sha256 -ne (Get-AgFileHash $cp)){throw 'renew_identity_change'}
   foreach($rule in $AllowedPaths){if(-not @($previous.allowed_paths|Where-Object {Test-AgRule $rule ([string]$_)}).Count){throw 'renew_scope_expansion'}}
  }
  $b=@{schema='antigravity-desktop-session-binding-v2';revision=if($previous){[int]$previous.revision+1}else{1};status='active';conversation_id_sha256=$hash;task_root=$task;task_root_sha256=(Get-AgHash $task.ToLowerInvariant());contract_path=$cp;contract_file_sha256=(Get-AgFileHash $cp);ledger_path=$lp;logical_task_id_sha256=(Get-AgHash ([string]$l.task_id));attempt_id=$AttemptId;attempt_id_sha256=(Get-AgHash $AttemptId);prior_attempt_id_sha256=if($previous){$previous.attempt_id_sha256}else{$null};role=$Role;allowed_paths=@($AllowedPaths);authority='operator-script-unattested';created_at=[DateTime]::UtcNow.ToString('o');expires_at=[DateTime]::UtcNow.AddMinutes($ExpiresInMinutes).ToString('o')}
  Write-AgAtomic $path $b
  $marker=Join-Path $state '.gemini-private';if(-not(Test-Path -LiteralPath $marker)){[IO.File]::WriteAllText($marker,'')}
  return @{status='success';binding=$path;revision=$b.revision;authority=$b.authority;expires_at=$b.expires_at}
 };$result|ConvertTo-Json -Compress
}catch{@{status='error';error_code='desktop_session_binding_failed'}|ConvertTo-Json -Compress}
