param([string]$CodexHome = (Join-Path $PSScriptRoot '..'),[string]$ProjectRoot='')
$ErrorActionPreference = 'Stop'
if($ProjectRoot){$CodexHome=Join-Path $ProjectRoot 'src'}
$entry = Join-Path $CodexHome 'scripts/invoke-agent-handoff.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('handoff-regression-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks = New-Object 'System.Collections.Generic.List[object]'
function Assert-Case([string]$Name, [bool]$Pass) {
    $checks.Add([pscustomobject]@{name=$Name; passed=$Pass})
    if (-not $Pass) { throw "FAILED: $Name" }
}
function Invoke-Handoff([hashtable]$Extra) {
    $invokeParameters = @{ProjectRoot=$root;TaskId='task-1'}
    foreach ($key in $Extra.Keys) { $invokeParameters[$key]=$Extra[$key] }
    return (& $entry @invokeParameters | ConvertFrom-Json)
}
function Assert-Rejected([string]$Name,[hashtable]$Overrides,[string]$Reason='') {
    $failed=$false
    try { Invoke-Handoff $Overrides | Out-Null } catch { $failed=(-not $Reason -or $_.Exception.Message -match $Reason) }
    Assert-Case $Name $failed
}
Assert-Case 'entry-exists' (Test-Path -LiteralPath $entry)
$s=Invoke-Handoff @{Action='Init';Engine='codex';Objective='Fix parser';AllowedPaths=@('src/parser.ps1');RequiredChecks=@('parser-unit')}
Assert-Case 'codex-targeted-init' ($s.task.verification_policy -eq 'codex-targeted')
$s=Invoke-Handoff @{Action='Acquire';Engine='codex';SessionRef='codex-a';ExpectedRevision=$s.task.revision}
$token=$s.task.writer.token
Assert-Case 'writer-acquired' ($s.task.writer.engine -eq 'codex')
Assert-Rejected 'same-task-collision' @{Action='Acquire';Engine='antigravity';SessionRef='ag-a';ExpectedRevision=$s.task.revision}
Assert-Rejected 'wrong-owner-cannot-release' @{Action='Release';Engine='codex';SessionRef='codex-b';Token=$token;ExpectedRevision=$s.task.revision}
Assert-Rejected 'stale-revision-rejected' @{Action='Release';Engine='codex';SessionRef='codex-a';Token=$token;ExpectedRevision=1}
$other=Invoke-Handoff @{Action='Init';TaskId='task-2';Engine='codex';Objective='Second task';AllowedPaths=@('other.txt');RequiredChecks=@('unit')}
Assert-Rejected 'checkout-wide-collision' @{Action='Acquire';TaskId='task-2';Engine='codex';SessionRef='codex-b';ExpectedRevision=$other.task.revision}
$s=Invoke-Handoff @{Action='Handoff';Engine='codex';SessionRef='codex-a';Token=$token;ExpectedRevision=$s.task.revision;TargetEngine='antigravity';NextAction='Implement parser under the existing required checks'}
Assert-Case 'handoff-to-ag-escalates' ($s.task.verification_policy -eq 'antigravity-strict')
Assert-Case 'handoff-releases-writer' ($null -eq $s.task.writer)
$s=Invoke-Handoff @{Action='Acquire';Engine='antigravity';SessionRef='ag-a';ExpectedRevision=$s.task.revision}
$token=$s.task.writer.token
Assert-Case 'ag-provenance-recorded' (@($s.task.producer_engines) -contains 'antigravity')
New-Item -ItemType Directory -Path (Join-Path $root 'artifacts/checks') -Force | Out-Null
$proof=Join-Path $root 'artifacts/checks/proof.json'
[IO.File]::WriteAllText($proof,'{"status":"passed","exit_code":0}',(New-Object Text.UTF8Encoding($false)))
$s=Invoke-Handoff @{Action='RecordEvidence';Engine='antigravity';SessionRef='ag-a';Token=$token;ExpectedRevision=$s.task.revision;CheckId='parser-unit';EvidencePath='artifacts/checks/proof.json'}
Assert-Case 'evidence-does-not-accept-task' ($s.task.acceptance_status -eq 'unverified' -and $s.task.evidence[0].status -eq 'reference-only')
$s=Invoke-Handoff @{Action='Handoff';Engine='antigravity';SessionRef='ag-a';Token=$token;ExpectedRevision=$s.task.revision;TargetEngine='codex';NextAction='Review strict original evidence'}
Assert-Case 'strict-policy-survives-return' ($s.task.verification_policy -eq 'antigravity-strict' -and $s.task.required_checks[0] -eq 'parser-unit')
$s=Invoke-Handoff @{Action='Acquire';Engine='codex';SessionRef='codex-review';ExpectedRevision=$s.task.revision}
$token=$s.task.writer.token
Assert-Case 'codex-review-does-not-downgrade' ($s.task.verification_policy -eq 'antigravity-strict')
Assert-Rejected 'evidence-outside-project-with-valid-owner' @{Action='RecordEvidence';Engine='codex';SessionRef='codex-review';Token=$token;ExpectedRevision=$s.task.revision;CheckId='parser-unit';EvidencePath='../proof.json'} 'Unsafe relative path segment'
[IO.File]::WriteAllText($proof,'{"status":"changed"}',(New-Object Text.UTF8Encoding($false)))
Assert-Rejected 'record-changed-evidence-refused' @{Action='RecordEvidence';Engine='codex';SessionRef='codex-review';Token=$token;ExpectedRevision=$s.task.revision;CheckId='parser-unit';EvidencePath='artifacts/checks/proof.json'} 'already recorded with different content'
$status=Invoke-Handoff @{Action='Status'}
Assert-Case 'changed-evidence-detected' ($status.evidence_current -eq $false)
Assert-Rejected 'stale-evidence-blocks-handoff' @{Action='Handoff';Engine='codex';SessionRef='codex-review';Token=$token;ExpectedRevision=$s.task.revision;TargetEngine='antigravity';NextAction='continue'}
# Populate the bounded live-history edge without changing revision/ownership.
$edgePath=Join-Path $root 'artifacts/agent-collaboration/task-1/task.json'
$edge=Get-Content -LiteralPath $edgePath -Raw | ConvertFrom-Json
$edge.history=@(1..256 | ForEach-Object {[pscustomobject]@{revision=$_;action='Renew';engine='codex';at='2026-09-10T00:00:00Z'}})
[IO.File]::WriteAllText($edgePath,($edge | ConvertTo-Json -Depth 16),(New-Object Text.UTF8Encoding($false)))
$s=Invoke-Handoff @{Action='Release';Engine='codex';SessionRef='codex-review';Token=$token;ExpectedRevision=$s.task.revision}
Assert-Case 'stale-evidence-can-release-without-passing' ($null -eq $s.task.writer -and $s.task.acceptance_status -eq 'unverified')
Assert-Case 'history-limit-does-not-lock-checkout' (@($s.task.history).Count -eq 256 -and $null -eq $s.task.writer)
Assert-Case 'release-allows-explicit-next-engine-choice' ([string]::IsNullOrEmpty([string]$s.task.next_engine))
$partial=Invoke-Handoff @{Action='Acquire';Engine='antigravity';SessionRef='ag-resume';ExpectedRevision=$s.task.revision}
Assert-Case 'incomplete-work-resumes-without-acceptance' ($partial.task.verification_policy -eq 'antigravity-strict' -and $partial.task.acceptance_status -eq 'unverified' -and -not $partial.evidence_current)
$s=Invoke-Handoff @{Action='Release';Engine='antigravity';SessionRef='ag-resume';Token=$partial.task.writer.token;ExpectedRevision=$partial.task.revision}
Assert-Rejected 'task-traversal' @{Action='Init';TaskId='../escape';Objective='bad';AllowedPaths=@('a');RequiredChecks=@('unit')}
Assert-Rejected 'allowed-path-traversal' @{Action='Init';TaskId='bad-1';Objective='bad';AllowedPaths=@('../escape');RequiredChecks=@('unit')}
Assert-Rejected 'allowed-control-path' @{Action='Init';TaskId='bad-2';Objective='bad';AllowedPaths=@('.git/config');RequiredChecks=@('unit')}
Assert-Rejected 'allowed-ads-path' @{Action='Init';TaskId='bad-3';Objective='bad';AllowedPaths=@('file:stream');RequiredChecks=@('unit')}
Assert-Rejected 'missing-check-contract' @{Action='Init';TaskId='bad-4';Objective='bad';AllowedPaths=@('a')}
Assert-Rejected 'released-owner-cannot-add-evidence' @{Action='RecordEvidence';Engine='codex';SessionRef='codex-review';Token=$token;ExpectedRevision=$s.task.revision;CheckId='parser-unit';EvidencePath='artifacts/checks/proof.json'} 'Writer ownership mismatch'

# Actual process contention: only one acquisition can succeed at a shared revision.
$race=Invoke-Handoff @{Action='Init';TaskId='race';Engine='codex';Objective='Race';AllowedPaths=@('src/a');RequiredChecks=@('unit')}
$procs=@()
foreach($actor in @('actor-a','actor-b')) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName='powershell.exe'
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$entry+'" -Action Acquire -ProjectRoot "'+$root+'" -TaskId race -Engine codex -SessionRef '+$actor+' -ExpectedRevision '+$race.task.revision
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start()
    $procs+=@{Process=$p;Out=$p.StandardOutput.ReadToEndAsync();Err=$p.StandardError.ReadToEndAsync()}
}
$passed=0
foreach($item in $procs) {
    if(-not $item.Process.WaitForExit(15000)){ $item.Process.Kill();throw 'race process timeout' }
    [void]$item.Out.Result;[void]$item.Err.Result
    if($item.Process.ExitCode -eq 0){$passed++}
    $item.Process.Dispose()
}
Assert-Case 'concurrent-process-acquire-single-winner' ($passed -eq 1)
[pscustomobject]@{schema='agent-handoff-tests-v1';status='passed';count=$checks.Count;checks=$checks;retained_fixture=$root} | ConvertTo-Json -Depth 8
