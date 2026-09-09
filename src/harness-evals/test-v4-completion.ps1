param([string]$ProjectRoot = '')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$audit=Join-Path $ProjectRoot 'src/scripts/audit-governed-execution.ps1'
$gate=Join-Path $ProjectRoot 'src/scripts/invoke-completion-gate.ps1'
$stop=Join-Path $ProjectRoot 'src/scripts/invoke-bounded-stop.ps1'
$cases=New-Object 'System.Collections.Generic.List[string]'
function Assert($ok,$message){if(-not $ok){throw $message};$cases.Add($message)|Out-Null}
Assert ((Get-Content $audit -Raw) -notmatch 'function Latest-Json') 'explicit-chain-no-latest-selection'
Assert ((Get-Command $audit).Parameters.ContainsKey('DecisionPath')) 'explicit-decision-required'
Assert ((Get-Command $gate).Parameters.ContainsKey('ReadOnly')) 'read-only-gate-available'
Assert (Test-Path $stop) 'bounded-stop-implemented'
Assert ((Get-Command (Join-Path $ProjectRoot 'src/scripts/new-completion-claim.ps1')).Parameters.ContainsKey('ToolOperationPaths')) 'explicit-tool-operation-references-implemented'
$tmp=Join-Path $env:TEMP ('ag-v4c-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory $tmp|Out-Null
$state=Join-Path $tmp 'stop.json'
foreach($n in 1..3){$r=& $stop -StatePath $state -TaskId 'task' -DecisionStatus unverified|ConvertFrom-Json;Assert ($r.retry_count -eq [Math]::Min($n,2)) ('stop-count-'+$n)}
Assert ($r.action -eq 'stop' -and $r.status -eq 'blocked') 'stop-never-loops-after-two'
$cancel=& $stop -StatePath $state -TaskId task -DecisionStatus unverified -UserCancelled|ConvertFrom-Json
Assert ($cancel.action -eq 'stop' -and $cancel.status -eq 'cancelled') 'cancel-priority'
$disable=& $stop -StatePath $state -TaskId task -DecisionStatus unverified -EmergencyDisabled|ConvertFrom-Json
Assert ($disable.action -eq 'stop' -and $disable.status -eq 'disabled') 'disable-priority'
$missing=& $audit -ProjectRoot $ProjectRoot -TaskRoot $tmp -NoThrow|ConvertFrom-Json
Assert ($missing.status -eq 'failed' -and 'decision-reference-required' -in $missing.failures) 'missing-reference-fails-visible'
function JsonFile($path,$value){New-Item -ItemType Directory -Force (Split-Path -Parent $path)|Out-Null;[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 24),(New-Object Text.UTF8Encoding($false)))}
$scripts=Join-Path $ProjectRoot 'src/scripts'
[IO.File]::WriteAllText((Join-Path $tmp 'source.txt'),'source')
$testCode=@'
New-Item -ItemType Directory -Force 'artifacts/test-results'|Out-Null
[IO.File]::WriteAllText((Join-Path (Get-Location).Path 'artifacts/test-results/current.json'),'{"schema":"antigravity-test-result-v1","cases":[{"id":"current-input","status":"passed"}]}')
'@
[IO.File]::WriteAllText((Join-Path $tmp 'test.ps1'),$testCode)
$contract=& (Join-Path $scripts 'new-task-contract.ps1') -ProjectRoot $tmp -StateRoot (Join-Path $tmp 'harness-state') -ContractId task -Objective 'completion fixture' -AllowedPaths source.txt -RequiredChecks current-input|ConvertFrom-Json
JsonFile (Join-Path $tmp 'harness-state/task-root.json') @{logical_task_id='task'}
$attempt=& (Join-Path $scripts 'new-attempt-record.ps1') -ProjectRoot $tmp -StateRoot (Join-Path $tmp 'harness-state') -TaskId task -OperationId verify -AttemptId attempt -InputPaths source.txt|ConvertFrom-Json
$envResult=& (Join-Path $scripts 'invoke-verification-envelope.ps1') -ProjectRoot $tmp -Name current -Command "& './test.ps1'" -SourcePaths source.txt -TestPaths test.ps1 -TestResultPath 'artifacts/test-results/current.json' -AcceptanceCriteria current-input -RequireStructuredTestResult -RequireSourcePaths -RequireTestPaths -TaskId task -TaskAttemptId attempt -ContractPath $contract.path|ConvertFrom-Json
$null=& (Join-Path $scripts 'update-attempt-record.ps1') -LedgerPath $attempt.path -AttemptId attempt -ExpectedVersion 1 -Status passed -ExitCode 0 -EvidenceArtifact $envResult.manifest
$report=& (Join-Path $scripts 'render-completion-report.ps1') -LedgerPath $attempt.path|ConvertFrom-Json
$claimParams=@{ProjectRoot=$tmp;ContractPath=$contract.path;EnvelopePath=$envResult.manifest;LedgerPath=$attempt.path;ReportPath=$report.report;TestResultPath='artifacts/test-results/current.json';AcceptanceCriterionIds=@('current-input');ClaimSummary='fixture';ActorRole='reviewer';ActorId='fixture';CheckerRole='reviewer';CheckerIndependent=$true}
$claim=& (Join-Path $scripts 'new-completion-claim.ps1') @claimParams|ConvertFrom-Json
Assert ($claim.status -eq 'success') 'canonical-claim-created'
$decision=& $gate -ProjectRoot $tmp -ClaimPath $claim.claim|ConvertFrom-Json
Assert ($decision.decision_status -eq 'checking') 'canonical-chain-remains-checking'
$auditResult=& $audit -ProjectRoot $ProjectRoot -TaskRoot $tmp -DecisionPath $decision.decision -NoThrow|ConvertFrom-Json
Assert ($auditResult.status -eq 'passed' -and $auditResult.completion_status -eq 'checking') 'explicit-audit-canonical-chain'
. (Join-Path $scripts 'resolve-desktop-control-library.ps1')
Set-StrictMode -Off
$eventOverride=$env:ANTIGRAVITY_HOOK_PROBE_STATE_ROOT
try{
 $env:ANTIGRAVITY_HOOK_PROBE_STATE_ROOT=Join-Path $tmp 'artifacts/operation-fixture'
 $hostInput=@{conversationId='completion-fixture';stepIdx=1;toolCall=@{name='write_to_file';args=@{TargetFile=Join-Path $tmp 'source.txt'}};error=''}
 $auth=@{decision='allow';reason_code='fixture';task_id_sha256=Get-AgHash 'task';attempt_id_sha256=Get-AgHash 'attempt';task_root_sha256=Get-AgHash ((Get-AgPath $tmp).ToLowerInvariant());binding_revision=1}
 $null=Add-AgOperation $hostInput Pre $auth
 $opResult=Add-AgOperation $hostInput Post
 $operationPath=Join-Path $env:ANTIGRAVITY_HOOK_PROBE_STATE_ROOT ('operations/'+(Get-AgHash 'completion-fixture').Substring(0,16)+'/'+$opResult.operation_id+'.json')
 $opParams=$claimParams.Clone();$opParams.ToolOperationPaths=@($operationPath)
 $opClaim=& (Join-Path $scripts 'new-completion-claim.ps1') @opParams|ConvertFrom-Json
 $r=& $gate -ProjectRoot $tmp -ClaimPath $opClaim.claim -ReadOnly|ConvertFrom-Json
 if($r.status -ne 'checking'){throw ('operation fixture failures: '+($r.failures -join ','))}
 Assert ($r.status -eq 'checking' -and $r.checks.operation_coverage -eq 'explicit_subset' -and -not $r.checks.hook_completeness_verified) 'explicit-completed-operation-is-not-acceptance-authority'
 $originalOp=Get-Content -LiteralPath $operationPath -Raw
 $mutatedOp=$originalOp|ConvertFrom-Json;$mutatedOp.task_id_sha256='f'*64;JsonFile $operationPath $mutatedOp
 $r=& $gate -ProjectRoot $tmp -ClaimPath $opClaim.claim -ReadOnly|ConvertFrom-Json
 Assert ('operation-evidence-replaced' -in $r.failures -and 'operation-task-reference-mismatch' -in $r.failures) 'changed-cross-task-operation-rejected'
 $mutatedOp=$originalOp|ConvertFrom-Json;$mutatedOp.callbacks=@($mutatedOp.callbacks[0]);$mutatedOp.revision=1;$mutatedOp.status='unresolved';JsonFile $operationPath $mutatedOp
 $r=& $gate -ProjectRoot $tmp -ClaimPath $opClaim.claim -ReadOnly|ConvertFrom-Json
 Assert ('operation-unresolved' -in $r.failures) 'missing-post-operation-not-complete'
 [IO.File]::WriteAllText($operationPath,$originalOp,(New-Object Text.UTF8Encoding($false)))
}finally{$env:ANTIGRAVITY_HOOK_PROBE_STATE_ROOT=$eventOverride}
$original=Get-Content -LiteralPath $claim.claim -Raw|ConvertFrom-Json
$original.task_id='other'
$mutated=Join-Path $tmp 'artifacts/claims/wrong-task.json';JsonFile $mutated $original
$r=& $gate -ProjectRoot $tmp -ClaimPath $mutated -ReadOnly|ConvertFrom-Json
Assert ('task-attempt-reference-mismatch' -in $r.failures) 'cross-task-rejected'
$original=Get-Content -LiteralPath $claim.claim -Raw|ConvertFrom-Json
$original.test_result.sha256='f'*64;JsonFile $mutated $original
$r=& $gate -ProjectRoot $tmp -ClaimPath $mutated -ReadOnly|ConvertFrom-Json
Assert ('test-result-reference-mismatch' -in $r.failures) 'replaced-evidence-rejected'
$original=Get-Content -LiteralPath $claim.claim -Raw|ConvertFrom-Json
$original.producer_script_sha256='f'*64;JsonFile $mutated $original
$r=& $gate -ProjectRoot $tmp -ClaimPath $mutated -ReadOnly|ConvertFrom-Json
Assert ('claim-provenance-invalid' -in $r.failures -and $r.status -ne 'verified') 'forged-producer-no-authority'
$before=(Get-FileHash -LiteralPath $claim.claim).Hash
$overwrite=$claimParams.Clone();$overwrite.OutputPath=$claim.claim
$r=& (Join-Path $scripts 'new-completion-claim.ps1') @overwrite|ConvertFrom-Json
Assert ($r.status -eq 'error' -and (Get-FileHash -LiteralPath $claim.claim).Hash -eq $before) 'prior-claim-preserved'
$contractText=[IO.File]::ReadAllText($contract.path)
$changedContract=$contractText|ConvertFrom-Json;$changedContract.required_checks=@('current-input','missing-check');JsonFile $contract.path $changedContract
$r=& $gate -ProjectRoot $tmp -ClaimPath $claim.claim -ReadOnly|ConvertFrom-Json
Assert ('required-check-missing' -in $r.failures) 'contract-required-check-cannot-be-omitted'
[IO.File]::WriteAllText($contract.path,$contractText,(New-Object Text.UTF8Encoding($false)))
$envelope=Get-Content -LiteralPath $envResult.manifest -Raw|ConvertFrom-Json
$envelope.script_sha256='f'*64
$oldEnvelope=Join-Path $tmp 'artifacts/old/envelope.json';JsonFile $oldEnvelope $envelope
$original=Get-Content -LiteralPath $claim.claim -Raw|ConvertFrom-Json
$original.verification.envelope_path='artifacts/old/envelope.json';$original.verification.envelope_sha256=(Get-FileHash -LiteralPath $oldEnvelope).Hash.ToLowerInvariant()
JsonFile $mutated $original
$r=& $gate -ProjectRoot $tmp -ClaimPath $mutated -ReadOnly|ConvertFrom-Json
Assert ('envelope-producer-stale' -in $r.failures) 'old-envelope-producer-invalidates-run'
$outside=Join-Path $tmp 'outside';New-Item -ItemType Directory $outside|Out-Null
$alias=Join-Path $tmp 'artifacts/alias';New-Item -ItemType Junction -Path $alias -Target $outside|Out-Null
$escape=$claimParams.Clone();$escape.OutputPath=Join-Path $alias 'escaped.json'
$r=& (Join-Path $scripts 'new-completion-claim.ps1') @escape|ConvertFrom-Json
Assert ($r.status -eq 'error' -and -not(Test-Path (Join-Path $outside 'escaped.json'))) 'claim-junction-output-rejected'
$r=& $stop -StatePath (Join-Path $alias 'must-not-exist/state.json') -TaskId task -DecisionStatus unverified|ConvertFrom-Json
Assert ($r.status -eq 'blocked' -and -not(Test-Path (Join-Path $outside 'must-not-exist'))) 'stop-junction-deny-has-no-parent-side-effect'
[IO.File]::WriteAllText((Join-Path $tmp 'test.ps1'),$testCode+"`n# changed")
$r=& $gate -ProjectRoot $tmp -ClaimPath $claim.claim -ReadOnly|ConvertFrom-Json
Assert ('test-state-changed' -in $r.failures -or 'input-written-after-verification' -in $r.failures) 'test-edit-invalidates-run'
[ordered]@{status='success';cases=$cases.ToArray();fixture_retained=$true;host_stop_activation='unverified'}|ConvertTo-Json -Compress
