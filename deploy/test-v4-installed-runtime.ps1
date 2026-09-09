param([string]$ProjectRoot='')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))}
$root=Join-Path $env:TEMP ('antigravity-installed-test-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
$runtime=Join-Path $root 'runtime';New-Item -ItemType Directory -Path $runtime|Out-Null
$sync=& (Join-Path $ProjectRoot 'deploy\sync-to-runtime.ps1') -ProjectRoot $ProjectRoot -GeminiHome $runtime|ConvertFrom-Json
if($sync.status -ne 'success'){throw 'Isolated runtime installation failed'}
# Transactional plugin tests use its accepted fixture/plugins shape. Copy its verified
# payload into the isolated normal runtime's real config layout to exercise resolution.
$pluginTarget=Join-Path $root 'plugins\antigravity-reliable-control'
$plugin=& (Join-Path $ProjectRoot 'deploy\install-desktop-hook-plugin.ps1') -ProjectRoot $ProjectRoot -TargetRoot $pluginTarget|ConvertFrom-Json
if($plugin.status -ne 'installed'){throw 'Isolated plugin installation failed'}
$configPlugins=Join-Path $runtime 'config\plugins';New-Item -ItemType Directory -Path $configPlugins -Force|Out-Null
Copy-Item -LiteralPath $pluginTarget -Destination (Join-Path $configPlugins 'antigravity-reliable-control') -Recurse
$scripts=Join-Path $runtime 'scripts';$task=Join-Path $root 'task';New-Item -ItemType Directory -Path $task|Out-Null
$taskState=Join-Path $task 'harness-state'
$c=& (Join-Path $scripts 'new-task-contract.ps1') -ProjectRoot $task -StateRoot $taskState -Objective 'Isolated v4 installed plumbing' -ContractId installed-case -AllowedPaths @('out.txt')|ConvertFrom-Json
$a=& (Join-Path $scripts 'new-attempt-record.ps1') -ProjectRoot $task -StateRoot $taskState -TaskId installed-case -OperationId fixture-write -AttemptId installed-attempt|ConvertFrom-Json
$ledger=Join-Path $taskState 'attempt-ledgers\installed-case.json'
$policy=Join-Path $root 'policy\projects.json';$bindings=Join-Path $root 'bindings'
$p=& (Join-Path $scripts 'register-desktop-project.ps1') -ProjectRoot $task -Mode guarded -PolicyPath $policy|ConvertFrom-Json
$b=& (Join-Path $scripts 'new-desktop-session-binding.ps1') -StateRoot $bindings -ConversationId installed-fixture -TaskRoot $task -ContractPath $c.path -LedgerPath $ledger -AttemptId installed-attempt|ConvertFrom-Json
if($c.status -ne 'success' -or $a.status -ne 'success' -or $p.status -ne 'success' -or $b.status -ne 'success'){throw 'Installed canonical binding failed'}
$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $pluginTarget 'hooks\pre-tool-use.ps1')+'"';$psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_PROBE_STATE_ROOT']=Join-Path $root 'events';$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_BINDING_STATE_ROOT']=$bindings;$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_POLICY_PATH']=$policy;$psi.EnvironmentVariables['ANTIGRAVITY_HOOK_BINDING_POLICY_ROOT']=''
$process=[Diagnostics.Process]::Start($psi);$value=@{conversationId='installed-fixture';stepIdx=1;workspacePaths=@($task);toolCall=@{name='write_to_file';args=@{TargetFile=(Join-Path $task 'out.txt')}}}
$process.StandardInput.Write(($value|ConvertTo-Json -Depth 8));$process.StandardInput.Close();$o=$process.StandardOutput.ReadToEndAsync();$e=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(10000)){$process.Kill();throw 'Installed hook timeout'}
if($process.ExitCode -ne 0 -or ($o.Result|ConvertFrom-Json).decision -ne 'allow'){throw 'Installed native-write admission failed'}
$audit=&(Join-Path $scripts 'audit-desktop-hook-session.ps1') -StateRoot (Join-Path $root 'events') -ConversationId installed-fixture|ConvertFrom-Json
if($audit.pre_count -ne 1 -or $audit.missing_post_count -ne 1 -or $audit.status -ne 'warning'){throw 'Installed unresolved truth failed'}
$summary=@{schema='antigravity-v4-installed-runtime-test';status='passed';runtime_files=$sync.copied_file_count;plugin_files=$plugin.file_count;runtime_manifest=$sync.transaction_manifest;plugin_manifest=$plugin.transaction_manifest;fixture=$root;native_desktop='not_executed';installed_binding='active';operation='unresolved'}
$out=Join-Path $ProjectRoot ('artifacts\v4\installed-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'.json');[IO.File]::WriteAllText($out,($summary|ConvertTo-Json -Depth 8));$summary|ConvertTo-Json -Compress
