param([string]$ProjectRoot='')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))}
$entry=Join-Path $ProjectRoot 'src/scripts/invoke-antigravity-handoff.ps1'
if(-not(Test-Path -LiteralPath $entry)){throw 'Strict adapter not implemented.'}
$work=Join-Path $env:TEMP ('strict-handoff-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$s=& $entry -Action Init -ProjectRoot $work -TaskId strict-task -Objective 'Strict implementation' -AllowedPaths src -RequiredChecks full-suite | ConvertFrom-Json
if($s.task.verification_policy -ne 'antigravity-strict'){throw 'Antigravity initialized with a weak policy.'}
$s=& $entry -Action Acquire -ProjectRoot $work -TaskId strict-task -SessionRef ag-session -ExpectedRevision $s.task.revision | ConvertFrom-Json
$blocked=$false
try {& $entry -Action Handoff -ProjectRoot $work -TaskId strict-task -SessionRef ag-session -ExpectedRevision $s.task.revision -Token $s.task.writer.token -TargetEngine codex -NextAction Review | Out-Null} catch {$blocked=$true}
if(-not $blocked){throw 'Missing native completion chain was accepted.'}
$native=Join-Path $work 'native';New-Item -ItemType Directory -Path (Join-Path $native 'harness-state') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $native 'harness-state/task-root.json'),'{"logical_task_id":"another-task"}')
$blocked=$false
try {& $entry -Action Handoff -ProjectRoot $work -TaskId strict-task -SessionRef ag-session -ExpectedRevision $s.task.revision -Token $s.task.writer.token -TargetEngine codex -NextAction Review -NativeTaskRoot $native -DecisionPath 'fake.json' | Out-Null} catch {$blocked=$true}
if(-not $blocked){throw 'Native task mismatch accepted.'}
$s=& $entry -Action Status -ProjectRoot $work -TaskId strict-task | ConvertFrom-Json
if(-not $s.task.writer -or $s.task.acceptance_status -ne 'unverified'){throw 'Failed gate released ownership or changed acceptance.'}
$s=& $entry -Action Release -ProjectRoot $work -TaskId strict-task -SessionRef ag-session -ExpectedRevision $s.task.revision -Token $s.task.writer.token | ConvertFrom-Json
if($null -ne $s.task.writer){throw 'Safe release failed.'}
@{status='passed';cases=5;retained_fixture=$work;native_desktop='unverified'} | ConvertTo-Json -Compress
