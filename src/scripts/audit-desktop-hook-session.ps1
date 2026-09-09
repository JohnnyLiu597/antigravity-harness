param(
 [string]$StateRoot='',
 [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ConversationId,
 [string[]]$ExpectedTools=@()
)
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
if(-not $StateRoot){$StateRoot=(Get-AgRoots).events}
$StateRoot=Get-AgPath $StateRoot
$ch=Get-AgHash $ConversationId
$issues=New-Object Collections.Generic.List[string]
$pre=@();$post=@();$operations=@();$pending=0
if(-not(Test-Path -LiteralPath (Join-Path $StateRoot '.gemini-private'))){$issues.Add('private_marker_missing')}
# Legacy evidence is readable, never rewritten or upgraded to v4 assurance.
foreach($phase in @('pre','post')){
 $dir=Join-Path $StateRoot ('correlations\'+$phase)
 if(Test-Path -LiteralPath $dir){
  foreach($file in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.json')){
   try{
    $null=Get-AgPath $file.FullName;$v=Read-AgJson $file.FullName
    if($v.schema -ne ('antigravity-hook-'+$phase+'-correlation-v1') -or -not $v.conversation_id_sha256 -or -not $v.correlation_id_sha256){throw 'schema'}
    if($v.conversation_id_sha256 -ne $ch){continue}
    if($phase -eq 'pre'){$pre+=@($v)}else{$post+=@($v)}
   }catch{$issues.Add('legacy_corrupt_or_invalid_json')}
  }
 }
}
$dir=Join-Path $StateRoot ('operations\'+$ch.Substring(0,16))
if(Test-Path -LiteralPath $dir){
 foreach($file in @(Get-ChildItem -LiteralPath $dir -File)){
  if($file.Name -match '\.pending-'){$pending++;continue}
  if($file.Extension -ne '.json'){continue}
  try{
   $null=Get-AgPath $file.FullName;$v=Read-AgJson $file.FullName
   Assert-AgOperation $v
   if($v.schema -ne 'antigravity-tool-operation-v1' -or $v.conversation_id_sha256 -ne $ch -or $v.operation_id -ne $file.BaseName -or $v.operation_id -ne (Get-AgHash ($ch+'|'+[string][int]$v.step_idx))){throw 'identity'}
   if(@($v.callbacks).Count -eq 0 -or $v.revision -ne @($v.callbacks).Count -or $v.status -ne (Get-AgOperationStatus $v)){throw 'state'}
   $operations+=@($v)
  }catch{$issues.Add('operation_corrupt_or_invalid_json')}
 }
}
if($pending){$issues.Add('incomplete_atomic_commit')}
$postIds=@{};foreach($p in $post){if($postIds.ContainsKey($p.correlation_id_sha256)){$issues.Add('duplicate_legacy_post')};$postIds[$p.correlation_id_sha256]=$p}
$missing=@($pre|Where-Object {$_.decision -eq 'allow' -and -not $postIds.ContainsKey($_.correlation_id_sha256)}).Count
$orphan=@($post|Where-Object correlation_status -eq 'orphan').Count
$denied=@($pre|Where-Object decision -eq 'deny').Count
$failed=@($post|Where-Object outcome -eq 'failed').Count
$completed=@($post|Where-Object outcome -eq 'succeeded').Count
$unclassified=@($post|Where-Object {$_.outcome -notin @('succeeded','failed')}).Count
$v4pre=0;$v4post=0;$tools=@($pre|ForEach-Object tool_name)
foreach($op in $operations){
 $pc=@($op.callbacks|Where-Object phase -eq 'Pre').Count;$qc=@($op.callbacks|Where-Object phase -eq 'Post').Count
 if($pc){$v4pre++;$tools+=@($op.tool_name)};if($qc){$v4post++}
 if($op.status -eq 'unresolved'){if($pc){$missing++}else{$orphan++}}
 if($op.status -eq 'denied'){$denied++}
 if($op.status -eq 'failed'){$failed++}
 if($op.status -eq 'completed'){$completed++}
 if($op.status -eq 'unclassified'){$unclassified++}
}
$tools=@($tools|Sort-Object -Unique);$missingTools=@($ExpectedTools|Where-Object {$_ -notin $tools})
if(($pre.Count+$operations.Count) -eq 0){$issues.Add('empty_ledger')}
if($missing){$issues.Add('missing_post_unresolved')};if($orphan){$issues.Add('orphan_post_unresolved')};if($unclassified){$issues.Add('unclassified_result')}
$byTool=@(foreach($name in $tools){
 $legacyPre=@($pre|Where-Object tool_name -eq $name);$legacyPost=@($post|Where-Object tool_name -eq $name);$ops=@($operations|Where-Object tool_name -eq $name)
 @{tool_name=$name;pre_count=$legacyPre.Count+@($ops|Where-Object {@($_.callbacks|Where-Object phase -eq 'Pre').Count}).Count;post_count=$legacyPost.Count+@($ops|Where-Object {@($_.callbacks|Where-Object phase -eq 'Post').Count}).Count;succeeded=@($legacyPost|Where-Object outcome -eq 'succeeded').Count+@($ops|Where-Object status -eq 'completed').Count;failed=@($legacyPost|Where-Object outcome -eq 'failed').Count+@($ops|Where-Object status -eq 'failed').Count;denied=@($legacyPre|Where-Object decision -eq 'deny').Count+@($ops|Where-Object status -eq 'denied').Count}
})
@{schema='antigravity-desktop-hook-session-audit-v2';status=if($issues.Count -or $missingTools.Count){'warning'}else{'success'};conversation_id_sha256=$ch;pre_count=$pre.Count+$v4pre;post_count=$post.Count+$v4post;matched_count=@($post|Where-Object correlation_status -eq 'matched').Count+@($operations|Where-Object {@($_.callbacks|Where-Object phase -eq 'Pre').Count -and @($_.callbacks|Where-Object phase -eq 'Post').Count}).Count;succeeded_count=$completed;failed_count=$failed;denied_count=$denied;missing_post_count=$missing;orphan_post_count=$orphan;unclassified_count=$unclassified;observed_tools=$tools;missing_expected_tools=$missingTools;by_tool=$byTool;issues=@($issues.ToArray());pending_commit_count=$pending;legacy_evidence_count=$pre.Count+$post.Count;operation_count=$operations.Count;assurance='execution-observation-not-task-acceptance';strict='unavailable'}|ConvertTo-Json -Depth 10 -Compress
