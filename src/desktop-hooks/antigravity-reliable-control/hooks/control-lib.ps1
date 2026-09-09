# Shared Antigravity Desktop v4 primitives. Same-user local state is NOT attestation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-AgField($Value,[string]$Name,$Default=$null) {
 if($null -eq $Value){return $Default}
 if($Value -is [Collections.IDictionary]){if($Value.Contains($Name)){return $Value[$Name]};return $Default}
 if($Value.PSObject.Properties.Name -contains $Name){return $Value.$Name};return $Default
}
function Get-AgHash([AllowEmptyString()][string]$Text) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-AgFileHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-AgSingleLink([string]$Path){
 if(-not ('Antigravity.FileLinks' -as [type])){Add-Type -TypeDefinition 'using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles; namespace Antigravity { public static class FileLinks { [StructLayout(LayoutKind.Sequential)] struct Info { public uint attr; public System.Runtime.InteropServices.ComTypes.FILETIME c,a,w; public uint vol,hi,lo,links,idxHi,idxLo; } [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i); public static uint Count(string p) { using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)) { Info i; if(!GetFileInformationByHandle(f.SafeFileHandle,out i)) throw new IOException("file_identity_unavailable"); return i.links; } } } }'|Out-Null}
 if([Antigravity.FileLinks]::Count($Path) -ne 1){throw 'hardlink_alias'}
}
function Read-AgJson([string]$Path) {
 $f=Get-Item -LiteralPath $Path -Force
 if($f.PSIsContainer -or $f.Length -gt 4194304 -or $f.Length -eq 0){throw 'invalid_json_size'}
 $v=[IO.File]::ReadAllText($f.FullName)|ConvertFrom-Json
 if($null -eq $v -or $v -is [array] -or $v -is [string]){throw 'invalid_json_object'}
 return $v
}
function Get-AgPath([string]$Path,[string]$Base='',[bool]$SkipFileIdentity=$false) {
 if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1f*?]' -or $Path.StartsWith('\\')){throw 'unsupported_path'}
 if($Path -match '^[A-Za-z]:[^\\/]' -or $Path -match ':(?![\\/])'){throw 'ads_or_drive_relative'}
 if(-not [IO.Path]::IsPathRooted($Path)){if(-not $Base){throw 'relative_without_base'};$Path=Join-Path $Base $Path}
 foreach($segment in ($Path -split '[\\/]')){if($segment -notin @('','.','..') -and $segment -match '[ .]$'){throw 'ambiguous_path_segment'}}
 $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
 # Refuse aliases with DOS reserved names. Canonicalize existing short names.
 if(($full -split '[\\/]')|Where-Object {$_ -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'}){throw 'device_path'}
 $cursor=$full
 while($cursor){
  if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'reparse_point'}}
  $parent=Split-Path -Parent $cursor;if(-not $parent -or $parent -eq $cursor){break};$cursor=$parent
 }
 if($full -match '~[0-9]'){
  if(-not ('Antigravity.LongPath' -as [type])){Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; namespace Antigravity { public static class LongPath { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern uint GetLongPathName(string p, StringBuilder b, uint n); } }'|Out-Null}
  $ancestor=$full;$tail=New-Object Collections.Generic.List[string]
  while(-not(Test-Path -LiteralPath $ancestor)){$tail.Insert(0,(Split-Path -Leaf $ancestor));$ancestor=Split-Path -Parent $ancestor;if(-not $ancestor){throw 'unresolved_alias'}}
  $buffer=New-Object Text.StringBuilder 32768
  $n=[Antigravity.LongPath]::GetLongPathName($ancestor,$buffer,32768)
  if($n -eq 0 -or $n -ge 32768){throw 'unresolved_alias'}
  $full=$buffer.ToString();foreach($part in $tail){$full=Join-Path $full $part}
 }
 if(-not $SkipFileIdentity -and (Test-Path -LiteralPath $full -PathType Leaf)){Assert-AgSingleLink $full}
 return $full.TrimEnd('\','/')
}
function Test-AgWithin([string]$Path,[string]$Root){return $Path.Equals($Root,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root.TrimEnd('\','/')+'\',[StringComparison]::OrdinalIgnoreCase)}
function Test-AgRule([string]$Relative,[string]$Rule){
 $p=$Relative.Replace('\','/');$r=$Rule.Replace('\','/')
 if($r -match '(^|/)\.\.(/|$)' -or $r.StartsWith('/') -or $r.Contains(':')){return $false}
 if($r.EndsWith('/')){return $p.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)}
 return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase)
}
function Get-AgRoots {
 $runtime=Join-Path $env:USERPROFILE '.gemini'
 return @{
  runtime=$runtime
  policy=if($env:ANTIGRAVITY_HOOK_POLICY_PATH){$env:ANTIGRAVITY_HOOK_POLICY_PATH}else{Join-Path $runtime 'harness-state\desktop-policy\projects.json'}
  bindings=if($env:ANTIGRAVITY_HOOK_BINDING_STATE_ROOT){$env:ANTIGRAVITY_HOOK_BINDING_STATE_ROOT}else{Join-Path $runtime 'harness-state\desktop-bindings'}
  events=if($env:ANTIGRAVITY_HOOK_PROBE_STATE_ROOT){$env:ANTIGRAVITY_HOOK_PROBE_STATE_ROOT}else{Join-Path $runtime 'harness-state\hook-probe'}
 }
}
function Invoke-AgLock([string]$LockPath,[scriptblock]$Body){
 $safe=Get-AgPath $LockPath '' $true;New-Item -ItemType Directory -Path (Split-Path -Parent $safe) -Force|Out-Null
 $watch=[Diagnostics.Stopwatch]::StartNew();$stream=$null
 while($null -eq $stream){try{$stream=[IO.File]::Open($safe,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{if($watch.ElapsedMilliseconds -gt 750){throw 'lock_timeout'};Start-Sleep -Milliseconds 15}}
 try{
  # Check link count on the acquired exclusive handle, not by reopening the lock.
  if(-not ('Antigravity.LockIdentity' -as [type])){Add-Type -TypeDefinition 'using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles; namespace Antigravity { public static class LockIdentity { [StructLayout(LayoutKind.Sequential)] struct Info { public uint attr; public System.Runtime.InteropServices.ComTypes.FILETIME c,a,w; public uint vol,hi,lo,links,idxHi,idxLo; } [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i); public static void Check(SafeFileHandle h) { Info i; if(!GetFileInformationByHandle(h,out i) || i.links!=1) throw new IOException("unsafe_lock_identity"); } } }'|Out-Null}
  [Antigravity.LockIdentity]::Check($stream.SafeFileHandle)
  &$Body
 }finally{$stream.Dispose()}
}
function Write-AgAtomic([string]$Path,$Value){
 $safe=Get-AgPath $Path;$parent=Split-Path -Parent $safe
 New-Item -ItemType Directory -Path $parent -Force|Out-Null
 $temp=$safe+'.pending-'+[guid]::NewGuid().ToString('N');$bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 32 -Compress))
 $s=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
 $null=Read-AgJson $temp;$null=Get-AgPath $safe
 if(Test-Path -LiteralPath $safe){[IO.File]::Replace($temp,$safe,$safe+'.previous-'+[guid]::NewGuid().ToString('N'))}else{[IO.File]::Move($temp,$safe)}
}
function Read-AgPolicy {
 $roots=Get-AgRoots
 if(Test-Path -LiteralPath $roots.policy){$null=Get-AgPath $roots.policy;$p=Read-AgJson $roots.policy;if($p.schema -ne 'antigravity-desktop-project-policy-v1'){throw 'policy_schema'};return $p}
 # Explicit legacy override is test/migration only; no hardcoded canary or ambient workspace.
 $projects=@()
 if($env:ANTIGRAVITY_HOOK_BINDING_POLICY_ROOT){$projects=@(@{project_root=(Get-AgPath $env:ANTIGRAVITY_HOOK_BINDING_POLICY_ROOT);mode='guarded';project_id='explicit-legacy-override'})}
 return @{schema='antigravity-desktop-project-policy-v1';revision=0;projects=$projects}
}
function Get-AgAuthorization($InputValue) {
 $answer=@{decision='deny';reason_code='authorization_unknown';binding_status='invalid';mode='unknown';task_id_sha256=$null;attempt_id_sha256=$null;task_root_sha256=$null;binding_revision=$null}
 try{
  $tool=[string](Get-AgField (Get-AgField $InputValue 'toolCall') 'name' '')
  $args=Get-AgField (Get-AgField $InputValue 'toolCall') 'args'
  if($tool -eq 'run_command' -and ([string](Get-AgField $args 'CommandLine' '')).Contains('ANTIGRAVITY_HOOK_DENY_SENTINEL_V1')){$answer.reason_code='sentinel-deny';return $answer}
  $policy=Read-AgPolicy;$roots=Get-AgRoots
  $conversation=[string](Get-AgField $InputValue 'conversationId' '')
  if(-not $conversation -or $null -eq (Get-AgField $InputValue 'stepIdx')){throw 'invalid_identity'}
  $writes=@('write_to_file','replace_file_content','multi_replace_file_content');$opaque=@('run_command','invoke_subagent','manage_subagents')
  $workspaces=@(Get-AgField $InputValue 'workspacePaths' @())
  $base=if($workspaces.Count -eq 1){Get-AgPath ([string]$workspaces[0])}else{''}
  $target='';if($tool -in $writes){$target=[string](Get-AgField $args 'TargetFile' (Get-AgField $args 'AbsolutePath' ''));$target=Get-AgPath $target $base}
  if($target){
   $controls=@($roots.policy,$roots.bindings,$roots.events,(Split-Path -Parent $PSScriptRoot),(Join-Path $roots.runtime 'scripts'),(Join-Path $roots.runtime 'schemas'),(Join-Path $roots.runtime 'harness-state'),(Join-Path $roots.runtime 'config\plugins\antigravity-reliable-control'),(Join-Path $roots.runtime 'AGENTS.md'),(Join-Path $roots.runtime 'GEMINI.md'))
   foreach($control in $controls){if(Test-AgWithin $target (Get-AgPath $control)){$answer.reason_code='control_plane_target';return $answer}}
  }
  $bindingPath=Join-Path $roots.bindings ('sessions\'+(Get-AgHash $conversation)+'.json');$binding=$null
  if(Test-Path -LiteralPath $bindingPath){$null=Get-AgPath $bindingPath;$binding=Read-AgJson $bindingPath}
  $protected=@()
  foreach($project in @(Get-AgField $policy 'projects' @())){
   $pr=Get-AgPath ([string]$project.project_root)
   if([string]$project.mode -notin @('observe','guarded','strict')){throw 'invalid_mode'}
   if([string]$project.mode -eq 'observe'){continue}
   $match=$false
   if($target -and (Test-AgWithin $target $pr)){$match=$true}
   foreach($wp in $workspaces){$w=Get-AgPath ([string]$wp);if((Test-AgWithin $w $pr) -or (Test-AgWithin $pr $w)){$match=$true}}
   if($binding){$bt=Get-AgPath ([string]$binding.task_root);if((Test-AgWithin $bt $pr) -or (Test-AgWithin $pr $bt)){$match=$true}}
   if($match){$protected+=@($project)}
  }
  if($protected.Count -eq 0){$answer.decision='allow';$answer.reason_code='observe-allow';$answer.binding_status='not_applicable';$answer.mode='observe';return $answer}
  $answer.mode='guarded'
  if(@($protected|Where-Object mode -eq 'strict').Count){$answer.mode='strict';$answer.reason_code='strict_unavailable';return $answer}
  if($tool -in $opaque){$answer.reason_code='guarded_opaque_execution_unavailable';return $answer}
  if($tool -notin $writes){$answer.decision='allow';$answer.reason_code='guarded_read';$answer.binding_status='not_applicable';return $answer}
  if(-not $binding){$answer.binding_status='missing';$answer.reason_code='session-binding-missing';return $answer}
  $answer.binding_status='invalid'
  if($binding.schema -ne 'antigravity-desktop-session-binding-v2' -or $binding.conversation_id_sha256 -ne (Get-AgHash $conversation)){throw 'binding_identity'}
  if($binding.status -ne 'active'){$answer.binding_status='revoked';throw 'binding_revoked'}
  if([DateTimeOffset]::Parse($binding.expires_at) -le [DateTimeOffset]::UtcNow){$answer.binding_status='expired';throw 'binding_expired'}
  if([DateTimeOffset]::Parse($binding.created_at) -gt [DateTimeOffset]::UtcNow){throw 'binding_future'}
  $task=Get-AgPath ([string]$binding.task_root);$cp=Get-AgPath ([string]$binding.contract_path);$lp=Get-AgPath ([string]$binding.ledger_path)
  if(-not(Test-AgWithin $cp $task) -or -not(Test-AgWithin $lp $task)){throw 'binding_control_outside_task'}
  if($target -eq $cp -or $target -eq $lp -or (Test-AgWithin $target (Join-Path $task 'harness-state'))){$answer.reason_code='control_plane_target';return $answer}
  if((Get-AgFileHash $cp) -ne $binding.contract_file_sha256){$answer.binding_status='contract_changed';throw 'contract_changed'}
  $c=Read-AgJson $cp;$ledgerBefore=Get-AgFileHash $lp;$l=Read-AgJson $lp
  if($c.schema -ne 'antigravity-harness-task-contract-v2' -or $l.schema -ne 'antigravity-harness-attempt-ledger-v1'){throw 'task_schema'}
  if([string](Get-AgField $c.scope 'access' '') -ne 'write' -or [string](Get-AgField $c 'status' '') -ne 'draft'){throw 'contract_not_writable'}
  if([string]$c.contract_id -ne [string]$l.task_id -or (Get-AgHash ([string]$l.task_id)) -ne $binding.logical_task_id_sha256){throw 'task_identity'}
  if((Get-AgPath $c.scope.project_root) -ne $task -or (Get-AgPath $l.project_root) -ne $task){throw 'task_root_identity'}
  $attempt=@($l.attempts|Where-Object {[string]$_.attempt_id -eq [string]$binding.attempt_id})
  if($attempt.Count -ne 1 -or [string]$attempt[0].status -ne 'running'){$answer.binding_status='attempt_not_running';throw 'attempt_not_running'}
  if([string]$binding.role -notin @('maker','test-author')){$answer.binding_status='non_writer_role';throw 'readonly_role'}
  $attemptRole=[string](Get-AgField $attempt[0] 'role' '')
  if($attemptRole -and $attemptRole -ne $binding.role){throw 'role_conflict'}
  if(-not(Test-AgWithin $target $task) -or $target -eq $task){throw 'outside_task'}
  $relative=$target.Substring($task.Length+1).Replace('\','/')
  if($binding.role -eq 'test-author' -and -not $relative.StartsWith('tests/',[StringComparison]::OrdinalIgnoreCase)){throw 'role_scope'}
  if(@($c.scope.denied_paths|Where-Object{Test-AgRule $relative ([string]$_)}).Count -or -not @($c.scope.allowed_paths|Where-Object{Test-AgRule $relative ([string]$_)}).Count){throw 'contract_scope'}
  if(-not @(Get-AgField $binding 'allowed_paths' @()|Where-Object{Test-AgRule $relative ([string]$_)}).Count){throw 'binding_scope'}
  # Recheck snapshots immediately before response. This narrows, but cannot close host TOCTOU.
  if((Get-AgFileHash $cp) -ne $binding.contract_file_sha256 -or (Get-AgFileHash $lp) -ne $ledgerBefore){throw 'state_changed_during_check'}
  $null=Get-AgPath $target
  $current=Read-AgJson $bindingPath;if($current.revision -ne $binding.revision -or $current.status -ne 'active'){throw 'binding_changed_during_check'}
  $answer.decision='allow';$answer.reason_code='session-binding-active';$answer.binding_status='active'
  $answer.task_id_sha256=Get-AgHash ([string]$l.task_id);$answer.attempt_id_sha256=Get-AgHash ([string]$binding.attempt_id);$answer.task_root_sha256=Get-AgHash $task.ToLowerInvariant();$answer.binding_revision=$binding.revision
  return $answer
 }catch{if($answer.reason_code -eq 'authorization_unknown'){$answer.reason_code='session-binding-invalid'};return $answer}
}
function Assert-AgOperation($Record){
 $fields=@('schema','operation_id','conversation_id_sha256','step_idx','tool_name','task_id_sha256','attempt_id_sha256','task_root_sha256','binding_revision','claim_ref','gate_ref','revision','status','callbacks','integrity')
 foreach($name in @($Record.PSObject.Properties.Name)){if($name -notin $fields){throw 'operation_extra_field'}}
 foreach($name in $fields){if($name -notin @($Record.PSObject.Properties.Name)){throw 'operation_missing_field'}}
 if($Record.schema -ne 'antigravity-tool-operation-v1' -or $Record.callbacks -isnot [array] -or $Record.revision -isnot [int] -or $Record.step_idx -isnot [int] -or $Record.step_idx -lt 0){throw 'operation_shape'}
 if($Record.status -notin @('denied','completed','failed','unresolved','unclassified') -or $Record.tool_name -notin @('unknown','list_dir','view_file','write_to_file','replace_file_content','multi_replace_file_content','run_command','invoke_subagent','manage_subagents')){throw 'operation_enum'}
 foreach($name in @('operation_id','conversation_id_sha256','task_id_sha256','attempt_id_sha256','task_root_sha256')){if($null -ne $Record.$name -and ($Record.$name -isnot [string] -or $Record.$name -cnotmatch '^[a-f0-9]{64}$')){throw 'operation_hash'}}
 if($Record.revision -ne $Record.callbacks.Count -or $Record.callbacks.Count -gt 128){throw 'operation_revision'}
 foreach($cb in $Record.callbacks){
  $cbFields=@('phase','observed_at','decision','reason_code','args_sha256','error_observed','error_present','error_sha256','requested_exit_code','child_exit_code','host_result_code')
  foreach($name in @($cb.PSObject.Properties.Name)){if($name -notin $cbFields){throw 'callback_extra_field'}}
  foreach($name in $cbFields){if($name -notin @($cb.PSObject.Properties.Name)){throw 'callback_missing_field'}}
  if($cb.phase -notin @('Pre','DuplicatePre','Post') -or $cb.error_observed -isnot [bool] -or $cb.error_present -isnot [bool]){throw 'callback_shape'}
  if($cb.phase -ne 'Post' -and $cb.decision -notin @('allow','deny')){throw 'callback_decision'}
  foreach($name in @('args_sha256','error_sha256')){if($null -ne $cb.$name -and ($cb.$name -isnot [string] -or $cb.$name -cnotmatch '^[a-f0-9]{64}$')){throw 'callback_hash'}}
  foreach($name in @('requested_exit_code','child_exit_code','host_result_code')){if($null -ne $cb.$name){throw 'unattested_exit_field'}}
 }
}
function Get-AgOperationStatus($Record){
 $pre=@($Record.callbacks|Where-Object phase -eq 'Pre');$post=@($Record.callbacks|Where-Object phase -eq 'Post')
 if($pre.Count -eq 0){return 'unresolved'}
 if($Record.callbacks[0].phase -eq 'Post'){return 'unclassified'}
 if($pre[0].decision -eq 'deny'){return 'denied'}
 if(@($Record.callbacks|Where-Object phase -eq 'DuplicatePre').Count){return 'unclassified'}
 if($post.Count -eq 0){return 'unresolved'}
 if($post.Count -gt 1){return 'unclassified'}
 if(-not [bool](Get-AgField $post[0] 'error_observed' $false)){return 'unclassified'}
 if([bool]$post[0].error_present){return 'failed'}
 if($Record.tool_name -eq 'run_command' -or $Record.tool_name -eq 'unknown' -or $Record.callbacks[0].phase -eq 'Post'){return 'unclassified'}
 return 'completed'
}
function Add-AgOperation($InputValue,[ValidateSet('Pre','Post')][string]$Phase,$Authorization=$null){
 $conversation=[string](Get-AgField $InputValue 'conversationId' '');$step=Get-AgField $InputValue 'stepIdx'
 if(-not $conversation -or $null -eq $step -or [string]$step -notmatch '^\d{1,9}$'){throw 'invalid_host_identity'}
 $ch=Get-AgHash $conversation;$id=Get-AgHash ($ch+'|'+[string][int]$step);$roots=Get-AgRoots
 $state=Get-AgPath $roots.events;New-Item -ItemType Directory -Path $state -Force|Out-Null
 $marker=Join-Path $state '.gemini-private';if(-not(Test-Path -LiteralPath $marker)){[IO.File]::WriteAllText($marker,'')}
 $path=Join-Path $state ('operations\'+$ch.Substring(0,16)+'\'+$id+'.json')
 return Invoke-AgLock ($path+'.lock') {
  $record=if(Test-Path -LiteralPath $path){Read-AgJson $path}else{[pscustomobject]@{schema='antigravity-tool-operation-v1';operation_id=$id;conversation_id_sha256=$ch;step_idx=[int]$step;tool_name='unknown';task_id_sha256=$null;attempt_id_sha256=$null;task_root_sha256=$null;binding_revision=$null;claim_ref=$null;gate_ref=$null;revision=0;status='unresolved';callbacks=@();integrity='local-atomic-not-tamperproof'}}
  Assert-AgOperation $record
  if($record.operation_id -ne $id -or $record.conversation_id_sha256 -ne $ch){throw 'operation_identity'}
  if(@($record.callbacks).Count -ge 128){throw 'operation_capacity'}
  $admission=if($Phase -eq 'Pre'){[string]$Authorization.decision}else{'observe'}
  $callback=[ordered]@{phase=$Phase;observed_at=[DateTime]::UtcNow.ToString('o');decision=$null;reason_code=$null;args_sha256=$null;error_observed=$false;error_present=$false;error_sha256=$null;requested_exit_code=$null;child_exit_code=$null;host_result_code=$null}
  if($Phase -eq 'Pre'){
   $tool=[string](Get-AgField (Get-AgField $InputValue 'toolCall') 'name' '')
   if($tool -notin @('list_dir','view_file','write_to_file','replace_file_content','multi_replace_file_content','run_command','invoke_subagent','manage_subagents')){$tool='unknown'}
   if(@($record.callbacks|Where-Object phase -eq 'Pre').Count){$admission='deny';$callback.phase='DuplicatePre'}
   if(@($record.callbacks|Where-Object phase -eq 'Post').Count){$admission='deny'}
   $record.tool_name=$tool;$callback.decision=$admission;$callback.reason_code=if($admission -ne $Authorization.decision){'operation_replay_denied'}else{$Authorization.reason_code}
   $callback.args_sha256=Get-AgHash ((Get-AgField (Get-AgField $InputValue 'toolCall') 'args' @{})|ConvertTo-Json -Depth 24 -Compress)
   foreach($field in @('task_id_sha256','attempt_id_sha256','task_root_sha256','binding_revision')){$record.$field=Get-AgField $Authorization $field}
  }else{
   $errorText=[string](Get-AgField $InputValue 'error' '');$callback.error_present=-not [string]::IsNullOrWhiteSpace($errorText)
   $rawError=$null
   if($InputValue -is [Collections.IDictionary]){if($InputValue.Contains('error')){$rawError=$InputValue['error']}}elseif($InputValue.PSObject.Properties.Name -contains 'error'){$rawError=$InputValue.error}
   $callback.error_observed=$rawError -is [string]
   if($callback.error_present){$callback.error_sha256=Get-AgHash $errorText}
   $posts=@($record.callbacks|Where-Object phase -eq 'Post')
   if(@($posts|Where-Object {$_.error_sha256 -eq $callback.error_sha256 -and $_.error_present -eq $callback.error_present -and (Get-AgField $_ 'error_observed' $false) -eq $callback.error_observed}).Count){return @{status=$record.status;admission=$admission;operation_id=$id;duplicate=$true}}
  }
  $record.callbacks=@($record.callbacks)+@([pscustomobject]$callback);$record.revision=[int]$record.revision+1;$record.status=Get-AgOperationStatus $record
  Write-AgAtomic $path $record
  return @{status=$record.status;admission=$admission;operation_id=$id;duplicate=$false}
 }
}
function Read-AgHookInput {
 # Console.In's synchronized reader can block even its Async method on .NET 4.
 if(-not ('Antigravity.HookInput' -as [type])){Add-Type -TypeDefinition 'using System; using System.Text; using System.Threading.Tasks; namespace Antigravity { public static class HookInput { public static string Read(int timeout, int max) { var task=Task.Run(() => { var b=new StringBuilder(); var c=new char[4096]; int n; while((n=Console.In.Read(c,0,c.Length))>0) { if(b.Length+n>max) throw new InvalidOperationException("stdin_size"); b.Append(c,0,n); } return b.ToString(); }); if(!task.Wait(timeout)) throw new TimeoutException("stdin_timeout"); return task.Result; } } }'|Out-Null}
 $raw=[Antigravity.HookInput]::Read(1500,1048576)
 if($raw.Length -eq 0){throw 'stdin_empty'}
 $value=$raw|ConvertFrom-Json;if($null -eq $value){throw 'empty_input'};return $value
}
