param([string]$ProjectRoot = '')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
$hook=Join-Path $ProjectRoot 'src\desktop-hooks\antigravity-reliable-control\hooks\pre-tool-use.ps1'
$audit=Join-Path $ProjectRoot 'src\scripts\audit-desktop-hook-session.ps1'
$root=Join-Path $env:LOCALAPPDATA ('Temp\antigravity-v4-control-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force|Out-Null
function Run-Hook($value,$state,$policyRoot){
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$hook+'"'
 $psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $psi.EnvironmentVariables['ANTIGRAVITY_HOOK_PROBE_STATE_ROOT']=$state
 $psi.EnvironmentVariables['ANTIGRAVITY_HOOK_BINDING_POLICY_ROOT']=$policyRoot
 $psi.EnvironmentVariables['ANTIGRAVITY_HOOK_BINDING_STATE_ROOT']=(Join-Path $root 'bindings')
 $psi.EnvironmentVariables['ANTIGRAVITY_HOOK_POLICY_PATH']=(Join-Path $root 'policy.json')
 $p=[Diagnostics.Process]::Start($psi);$p.StandardInput.Write(($value|ConvertTo-Json -Depth 10));$p.StandardInput.Close()
 $o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();if($p.ExitCode -ne 0){throw 'hook_process_failed'}
 return ($o|ConvertFrom-Json)
}
$results=New-Object Collections.Generic.List[object]
function Case($id,[scriptblock]$check){try{&$check;$results.Add(@{id=$id;status='passed'})}catch{$results.Add(@{id=$id;status='failed';failure='assertion_failed'});Write-Host "FAIL $id"}}
$task=Join-Path $root 'task';New-Item -ItemType Directory -Path $task|Out-Null
$blockedState=Join-Path $root 'state-is-file';[IO.File]::WriteAllText($blockedState,'fixture')
$payload=@{conversationId='v4-fixture';stepIdx=1;workspacePaths=@($task);toolCall=@{name='write_to_file';args=@{TargetFile=(Join-Path $task 'out.txt')}}}
Case 'A-logging-failure-must-not-allow-protected-write' {if((Run-Hook $payload $blockedState $task).decision -ne 'deny'){throw 'deny_overwritten'}}
$state=Join-Path $root 'empty';New-Item -ItemType Directory -Path $state|Out-Null;[IO.File]::WriteAllText((Join-Path $state '.gemini-private'),'')
Case 'C-empty-ledger-not-success' {$r=&$audit -StateRoot $state -ConversationId 'none'|ConvertFrom-Json;if($r.status -eq 'success'){throw 'empty_success'}}
$pre=Join-Path $state 'correlations\pre';New-Item -ItemType Directory -Path $pre -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $pre 'bad.json'),'{broken')
Case 'C-bad-json-visible' {$r=&$audit -StateRoot $state -ConversationId 'none'|ConvertFrom-Json;if($r.status -eq 'success'){throw 'corrupt_success'}}
Case 'A-no-hardcoded-canary' {if([IO.File]::ReadAllText($hook).Contains('antigravity-v351-binding-task-case-02')){throw 'hardcoded'}}
$report=@{schema='antigravity-v4-test-result';cases=@($results.ToArray());fixture=$root;created_at=[DateTime]::UtcNow.ToString('o')}
$out=Join-Path $ProjectRoot 'artifacts\v4';New-Item -ItemType Directory -Path $out -Force|Out-Null
$file=Join-Path $out ('control-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'.json');[IO.File]::WriteAllText($file,($report|ConvertTo-Json -Depth 8))
Write-Output ($report|ConvertTo-Json -Depth 8 -Compress)
if(@($results|Where-Object status -eq 'failed').Count){exit 1}
