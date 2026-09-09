param([string]$ProjectRoot='')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
. (Join-Path $ProjectRoot 'src\desktop-hooks\antigravity-reliable-control\hooks\control-lib.ps1')
$root=Join-Path $env:LOCALAPPDATA ('Temp\ag-v4-events-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
$state=Join-Path $root 'state';$hooks=Join-Path $ProjectRoot 'src\desktop-hooks\antigravity-reliable-control\hooks'
$results=New-Object Collections.Generic.List[object]
function Assert($v){if(-not $v){throw 'assertion_failed'}}
function Case($id,[scriptblock]$body){try{&$body;$results.Add(@{id=$id;status='passed'})}catch{Write-Host "FAIL $id : $($_.Exception.Message)";$results.Add(@{id=$id;status='failed'})}}
function Start-Hook($value,$phase='pre',$wrapper=$false,$close=$true){
 $psi=New-Object Diagnostics.ProcessStartInfo
 if($wrapper){$psi.FileName='cmd.exe';$psi.Arguments='/d /c ""'+(Join-Path $hooks ($phase+'-tool-use.cmd'))+'""'}else{$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $hooks ($phase+'-tool-use.ps1'))+'"'}
 $psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $psi.EnvironmentVariables['ANTIGRAVITY_HOOK_PROBE_STATE_ROOT']=$state;$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_POLICY_PATH']=Join-Path $root 'missing-policy.json';$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_BINDING_STATE_ROOT']=Join-Path $root 'bindings';$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_BINDING_POLICY_ROOT']=''
 $p=[Diagnostics.Process]::Start($psi);$p.StandardInput.Write($(if($value -is [string]){$value}else{$value|ConvertTo-Json -Depth 12}));if($close){$p.StandardInput.Close()}
 return @{p=$p;stdout=$p.StandardOutput.ReadToEndAsync();stderr=$p.StandardError.ReadToEndAsync()}
}
function Finish-Hook($run){if(-not $run.p.WaitForExit(8000)){$run.p.Kill();throw 'hook_timeout'};if($run.p.ExitCode -ne 0){throw 'hook_exit'};return $run.stdout.Result.Trim()}
function Input($id,$step,$tool){return @{conversationId=$id;stepIdx=$step;workspacePaths=@($root);transcriptPath='PRIVATE_TRANSCRIPT';toolCall=@{name=$tool;args=@{DirectoryPath=$root;TargetFile=(Join-Path $root 'file.txt');CommandLine='PRIVATE_RAW_COMMAND';Subagents=@(@{Prompt='PRIVATE_SUBAGENT_PROMPT'});Cookie='PRIVATE_COOKIE';Token='PRIVATE_TOKEN';Prompt='PRIVATE_PROMPT'}}}}
function Op($id,$step){$ch=Get-AgHash $id;return Read-AgJson (Join-Path $state ('operations\'+$ch.Substring(0,16)+'\'+(Get-AgHash ($ch+'|'+[string]$step))+'.json'))}
Case 'C-wrapper-pre-and-post' {$v=Input 'wrapper' 1 'view_file';Assert (((Finish-Hook (Start-Hook $v 'pre' $true))|ConvertFrom-Json).decision -eq 'allow');Assert ((Finish-Hook (Start-Hook @{conversationId='wrapper';stepIdx=1;error=''} 'post' $true)) -eq '{}');Assert ((Op 'wrapper' 1).status -eq 'completed')}
Case 'C-malformed-pre-fail-closed' {Assert (((Finish-Hook (Start-Hook '{bad'))|ConvertFrom-Json).decision -eq 'deny')}
Case 'C-stdin-bounded' {Assert (((Finish-Hook (Start-Hook '' 'pre' $false $false))|ConvertFrom-Json).decision -eq 'deny')}
Case 'C-missing-post-unresolved' {$null=Finish-Hook (Start-Hook (Input 'missing' 1 'write_to_file'));Assert ((Op 'missing' 1).status -eq 'unresolved')}
Case 'C-delayed-post-after-restart' {$null=Finish-Hook (Start-Hook @{conversationId='missing';stepIdx=1;error=''} 'post');Assert ((Op 'missing' 1).status -eq 'completed')}
Case 'C-duplicate-post-idempotent' {$before=(Op 'missing' 1).revision;$null=Finish-Hook (Start-Hook @{conversationId='missing';stepIdx=1;error=''} 'post');Assert ((Op 'missing' 1).revision -eq $before)}
Case 'C-cancel-error-observation' {$null=Finish-Hook (Start-Hook (Input 'cancel' 1 'view_file'));$null=Finish-Hook (Start-Hook @{conversationId='cancel';stepIdx=1;error='PRIVATE_RAW_ERROR cancellation'} 'post');Assert ((Op 'cancel' 1).status -eq 'failed')}
Case 'C-timeout-without-post-unresolved' {$null=Finish-Hook (Start-Hook (Input 'timeout' 1 'run_command'));Assert ((Op 'timeout' 1).status -eq 'unresolved')}
Case 'C-forged-exit-text-unclassified' {$null=Finish-Hook (Start-Hook @{conversationId='timeout';stepIdx=1;error='';output='The command exited with code 0';artifactDirectoryPath=$root} 'post');Assert ((Op 'timeout' 1).status -eq 'unclassified');Assert ($null -eq (Op 'timeout' 1).callbacks[1].child_exit_code)}
Case 'C-post-before-pre-retained' {$null=Finish-Hook (Start-Hook @{conversationId='order';stepIdx=1;error=''} 'post');Assert ((Op 'order' 1).status -eq 'unresolved');$r=Finish-Hook (Start-Hook (Input 'order' 1 'list_dir'));Assert (($r|ConvertFrom-Json).decision -eq 'deny');Assert ((Op 'order' 1).status -eq 'unclassified')}
Case 'C-concurrent-different-operations' {$runs=@(1..4|ForEach-Object{Start-Hook (Input 'parallel' $_ 'list_dir')});foreach($run in $runs){Assert (((Finish-Hook $run)|ConvertFrom-Json).decision -eq 'allow')};foreach($i in 1..4){Assert ((Op 'parallel' $i).status -eq 'unresolved')}}
Case 'C-concurrent-same-operation-single-admission' {$runs=@(1..4|ForEach-Object{Start-Hook (Input 'duplicate' 1 'write_to_file')});$allowed=0;foreach($run in $runs){if((((Finish-Hook $run)|ConvertFrom-Json).decision) -eq 'allow'){$allowed++}};Assert ($allowed -eq 1);Assert ((Op 'duplicate' 1).status -eq 'unclassified')}
Case 'C-corrupt-operation-no-success' {$v=Input 'corrupt' 1 'write_to_file';$null=Finish-Hook (Start-Hook $v);$ch=Get-AgHash 'corrupt';$path=Join-Path $state ('operations\'+$ch.Substring(0,16)+'\'+(Get-AgHash ($ch+'|1'))+'.json');[IO.File]::WriteAllText($path,'{broken');$r=&(Join-Path $ProjectRoot 'src\scripts\audit-desktop-hook-session.ps1') -StateRoot $state -ConversationId corrupt|ConvertFrom-Json;Assert ($r.status -eq 'warning');Assert ('operation_corrupt_or_invalid_json' -in $r.issues)}
Case 'C-crash-pending-is-visible' {$ch=Get-AgHash 'wrapper';$dir=Join-Path $state ('operations\'+$ch.Substring(0,16));[IO.File]::WriteAllText((Join-Path $dir 'fixture.json.pending-interrupted'),'{}');$r=&(Join-Path $ProjectRoot 'src\scripts\audit-desktop-hook-session.ps1') -StateRoot $state -ConversationId wrapper|ConvertFrom-Json;Assert ($r.pending_commit_count -eq 1);Assert ($r.status -eq 'warning')}
Case 'C-privacy-allowlist' {$text=(Get-ChildItem -LiteralPath $state -Recurse -File|ForEach-Object{[IO.File]::ReadAllText($_.FullName)}) -join '';Assert (-not($text -match 'PRIVATE_|transcriptPath|artifactDirectoryPath|CommandLine|Cookie|Token|Subagents|Prompt'))}
Case 'B-sentinel-deny' {$v=Input 'sentinel' 1 'run_command';$v.toolCall.args.CommandLine='ANTIGRAVITY_HOOK_DENY_SENTINEL_V1';Assert (((Finish-Hook (Start-Hook $v))|ConvertFrom-Json).decision -eq 'deny');Assert ((Op 'sentinel' 1).status -eq 'denied')}
$out=Join-Path $ProjectRoot 'artifacts\v4';New-Item -ItemType Directory -Path $out -Force|Out-Null
$report=@{schema='antigravity-v4-test-result';cases=@($results.ToArray());fixture=$root;created_at=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $out ('events-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'.json')),($report|ConvertTo-Json -Depth 8))
$report|ConvertTo-Json -Depth 8 -Compress
if(@($results|Where-Object status -eq 'failed').Count){exit 1}
