param([string]$ProjectRoot = "", [string]$EvidencePath = "")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) { $ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")) }
$installer = Join-Path $ProjectRoot "deploy\install-desktop-hook-plugin.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("antigravity-plugin-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$source = Join-Path $root 'source'
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src\desktop-hooks\antigravity-reliable-control') -Destination $source -Recurse
$target = Join-Path $root 'plugins\antigravity-reliable-control'
$results = New-Object Collections.Generic.List[object]
function Assert([bool]$Ok, [string]$Message) { if (-not $Ok) { throw $Message } }
function Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $results.Add([ordered]@{name=$Name;status='passed'}) }
    catch { $results.Add([ordered]@{name=$Name;status='failed';reason=$_.Exception.Message}) }
}
function Reject([scriptblock]$Body) { $rejected=$false; try { & $Body | Out-Null } catch { $rejected=$true }; Assert $rejected 'Expected refusal, operation was accepted.' }
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Put([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false))) }

Case 'unrelated-plugin-target-refused' { Reject { & $installer -SourceRoot $source -TargetRoot (Join-Path $root 'plugins\unrelated') -DryRun } }
Case 'temp-root-not-isolated-plugin-refused' { Reject { & $installer -SourceRoot $source -TargetRoot (Join-Path $root 'antigravity-reliable-control') -DryRun } }
Case 'dry-run-no-target-created' {
    $r=& $installer -SourceRoot $source -TargetRoot $target -DryRun | ConvertFrom-Json
    Assert ($r.status -eq 'dry-run' -and -not (Test-Path -LiteralPath $target)) 'Dry run changed target.'
}
Case 'first-install-transaction-postcheck' {
    $script:first = & $installer -SourceRoot $source -TargetRoot $target | ConvertFrom-Json
    Assert ($first.status -eq 'installed') 'Initial install did not succeed.'
    $m=Get-Content -LiteralPath $first.transaction_manifest -Raw | ConvertFrom-Json
    Assert ($m.schema -eq 'antigravity-desktop-hook-install-v2' -and $m.status -eq 'installed') 'Transactional v2 journal absent.'
}
Case 'diagnose-read-only' {
    $before=Hash (Join-Path $target 'hooks.json')
    $r=& $installer -TargetRoot $target -Mode Diagnose | ConvertFrom-Json
    Assert ($r.status -eq 'healthy' -and $r.live_desktop_verified -eq $false) 'Diagnosis must separate static and desktop truth.'
    Assert ((Hash (Join-Path $target 'hooks.json')) -eq $before) 'Diagnosis mutated plugin.'
}
Case 'malformed-candidate-preserves-current' {
    $bad=Join-Path $root 'bad-source'; Copy-Item -LiteralPath $source -Destination $bad -Recurse
    Put (Join-Path $bad 'hooks.json') '{invalid-json'
    $before=Hash (Join-Path $target 'hooks.json')
    Reject { & $installer -SourceRoot $bad -TargetRoot $target }
    Assert ((Hash (Join-Path $target 'hooks.json')) -eq $before) 'Bad candidate changed active plugin.'
}
Case 'syntax-invalid-candidate-refused' {
    $bad=Join-Path $root 'bad-syntax'; Copy-Item -LiteralPath $source -Destination $bad -Recurse
    Put (Join-Path $bad 'hooks\pre-tool-use.ps1') 'function {'
    Reject { & $installer -SourceRoot $bad -TargetRoot $target }
}
Case 'external-hook-command-refused' {
    $bad=Join-Path $root 'bad-command'; Copy-Item -LiteralPath $source -Destination $bad -Recurse
    $hooks=Get-Content -LiteralPath (Join-Path $bad 'hooks.json') -Raw | ConvertFrom-Json
    $hooks.'antigravity-reliable-control-probe'.PreToolUse[0].hooks[0].command='..\outside.cmd'
    Put (Join-Path $bad 'hooks.json') ($hooks | ConvertTo-Json -Depth 12)
    Reject { & $installer -SourceRoot $bad -TargetRoot $target }
}
Case 'source-alternate-data-stream-refused' {
    $bad=Join-Path $root 'bad-stream'; Copy-Item -LiteralPath $source -Destination $bad -Recurse
    Set-Content -LiteralPath (Join-Path $bad 'plugin.json') -Stream hidden -Value 'untracked data'
    Reject { & $installer -SourceRoot $bad -TargetRoot $target -DryRun }
}
Case 'upgrade-removes-stale-only-by-retaining-previous' {
    Put (Join-Path $target 'stale.txt') 'old version extra file'
    $script:upgrade = & $installer -SourceRoot $source -TargetRoot $target | ConvertFrom-Json
    Assert (-not (Test-Path -LiteralPath (Join-Path $target 'stale.txt'))) 'Copy-in-place left stale file active.'
    Assert (Test-Path -LiteralPath (Join-Path $upgrade.backup 'stale.txt')) 'Previous file was lost.'
}
Case 'rollback-upgrade-restores-previous' {
    $r=& $installer -TargetRoot $target -RollbackManifest $upgrade.transaction_manifest | ConvertFrom-Json
    Assert ($r.status -eq 'rolled-back' -and (Test-Path -LiteralPath (Join-Path $target 'stale.txt'))) 'Rollback failed to restore prior exact version.'
}
Case 'disable-enable-are-recoverable-transactions' {
    $r=& $installer -TargetRoot $target -Mode Disable | ConvertFrom-Json
    Assert ($r.transaction_manifest -and (Test-Path -LiteralPath $r.backup)) 'Disable lacks recovery.'
    $h=Get-Content -LiteralPath (Join-Path $target 'hooks.json') -Raw | ConvertFrom-Json
    Assert ($h.'antigravity-reliable-control-probe'.enabled -eq $false) 'Disable did not disable.'
    & $installer -TargetRoot $target -Mode Enable | Out-Null
    $h=Get-Content -LiteralPath (Join-Path $target 'hooks.json') -Raw | ConvertFrom-Json
    Assert ($h.'antigravity-reliable-control-probe'.enabled -eq $true) 'Enable did not enable.'
    Assert (@(Get-ChildItem -LiteralPath $target -Filter '*.superseded' -Recurse).Count -eq 0) 'Journal backup leaked into active payload.'
}
foreach ($point in @('AfterStage','AfterBackup','AfterSwitch')) {
    Case ("fault-$point-recovers-prior-and-retains-evidence") {
        $before=Hash (Join-Path $target 'hooks.json')
        Reject { & $installer -SourceRoot $source -TargetRoot $target -TestFailurePoint $point }
        Assert ((Hash (Join-Path $target 'hooks.json')) -eq $before) 'Injected failure damaged active version.'
        $journals=@(Get-ChildItem -LiteralPath (Join-Path $root 'plugin-backups\antigravity-reliable-control') -Filter install-transaction.json -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } | Where-Object { $_.status -eq 'failed-recovered' })
        Assert ($journals.Count -gt 0) 'Failure journal not retained.'
    }
}
Case 'lock-contention-fails-bounded' {
    $lock=Join-Path $root 'plugin-backups\antigravity-reliable-control\install.lock'
    $handle=[IO.File]::Open($lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Reject { & $installer -SourceRoot $source -TargetRoot $target } } finally { $handle.Dispose() }
}
Case 'rollback-manifest-target-forgery-refused' {
    $r=& $installer -SourceRoot $source -TargetRoot $target | ConvertFrom-Json
    $m=Get-Content -LiteralPath $r.transaction_manifest -Raw | ConvertFrom-Json
    $m.target_root=Join-Path $root 'plugins\unrelated'
    Put $r.transaction_manifest ($m | ConvertTo-Json -Depth 20)
    Reject { & $installer -TargetRoot $target -RollbackManifest $r.transaction_manifest }
    $m.target_root=$target; Put $r.transaction_manifest ($m | ConvertTo-Json -Depth 20)
}
Case 'rollback-manifest-backup-forgery-refused' {
    $r=& $installer -SourceRoot $source -TargetRoot $target | ConvertFrom-Json
    $m=Get-Content -LiteralPath $r.transaction_manifest -Raw | ConvertFrom-Json
    $saved=$m.backup_root; $m.backup_root=$source
    Put $r.transaction_manifest ($m | ConvertTo-Json -Depth 20)
    Reject { & $installer -TargetRoot $target -RollbackManifest $r.transaction_manifest }
    $m.backup_root=$saved; Put $r.transaction_manifest ($m | ConvertTo-Json -Depth 20)
}
Case 'tampered-backup-refused-before-displacing-current' {
    $r=& $installer -SourceRoot $source -TargetRoot $target | ConvertFrom-Json
    $before=Hash (Join-Path $target 'hooks.json')
    $backupHooks=Join-Path $r.backup 'hooks.json'; $saved=Get-Content -LiteralPath $backupHooks -Raw
    Put $backupHooks '{}'
    Reject { & $installer -TargetRoot $target -RollbackManifest $r.transaction_manifest }
    Assert ((Hash (Join-Path $target 'hooks.json')) -eq $before) 'Rollback touched target before backup validation.'
    Put $backupHooks $saved
}
Case 'first-install-rollback-retains-displaced-version' {
    $fresh=Join-Path ([IO.Path]::GetTempPath()) ('antigravity-plugin-test-'+[guid]::NewGuid().ToString('N'))
    $freshTarget=Join-Path $fresh 'plugins\antigravity-reliable-control'
    $r=& $installer -SourceRoot $source -TargetRoot $freshTarget | ConvertFrom-Json
    & $installer -TargetRoot $freshTarget -RollbackManifest $r.transaction_manifest | Out-Null
    Assert (-not (Test-Path -LiteralPath $freshTarget)) 'First install rollback did not restore absence.'
    Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $r.transaction_manifest) -Directory -Filter 'displaced-*').Count -eq 1) 'Displaced candidate not preserved.'
}
Case 'junction-source-refused' {
    $linked=Join-Path $root 'linked-source'
    New-Item -ItemType Junction -Path $linked -Target $source | Out-Null
    Reject { & $installer -SourceRoot $linked -TargetRoot $target -DryRun }
}
Case 'junction-target-ancestor-refused' {
    $isolated=Join-Path ([IO.Path]::GetTempPath()) ('antigravity-plugin-test-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $isolated | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $isolated 'plugins') -Target (Join-Path $root 'plugins') | Out-Null
    Reject { & $installer -SourceRoot $source -TargetRoot (Join-Path $isolated 'plugins\antigravity-reliable-control') -DryRun }
}
Case 'crash-after-backup-requires-explicit-recovery' {
    $before=Hash (Join-Path $target 'hooks.json')
    Reject { & $installer -SourceRoot $source -TargetRoot $target -TestFailurePoint CrashAfterBackup }
    Assert (-not (Test-Path -LiteralPath $target)) 'Crash fixture did not stop between renames.'
    $r=& $installer -TargetRoot $target -Mode Diagnose | ConvertFrom-Json
    Assert ($r.status -eq 'recovery-required' -and @($r.pending_transactions).Count -eq 1) 'Interrupted transaction not diagnosed.'
    Reject { & $installer -SourceRoot $source -TargetRoot $target }
    & $installer -TargetRoot $target -RollbackManifest $r.pending_transactions[0] | Out-Null
    Assert ((Hash (Join-Path $target 'hooks.json')) -eq $before) 'Interrupted recovery lost previous version.'
}
$failed=@($results | Where-Object {$_.status -eq 'failed'}).Count
$report=[ordered]@{schema='antigravity-v4-deployment-tests-v1';status=if($failed){'failed'}else{'passed'};powershell=$PSVersionTable.PSVersion.ToString();cases=$results.Count;failed=$failed;results=@($results.ToArray());fixture_root=$root;coverage='Requirement cases only; code coverage unmeasured; no live desktop test.'}
if ($EvidencePath) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EvidencePath) | Out-Null; Put $EvidencePath ($report | ConvertTo-Json -Depth 10) }
$report | ConvertTo-Json -Depth 10
if ($failed) { throw "$failed deployment cases failed." }
