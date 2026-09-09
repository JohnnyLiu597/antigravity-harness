param([string]$ProjectRoot='', [string]$EvidencePath='')
$ErrorActionPreference='Stop'
if (-not $ProjectRoot) { $ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
$sync=Join-Path $ProjectRoot 'deploy\sync-to-runtime.ps1'
$fixture=Join-Path $env:TEMP ('antigravity-runtime-sync-test-'+[guid]::NewGuid().ToString('N'))
$cases=New-Object Collections.Generic.List[object]
function Put($path,$value){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)|Out-Null; [IO.File]::WriteAllText($path,$value,(New-Object Text.UTF8Encoding($false)))}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject([scriptblock]$body){$rejected=$false;try{& $body|Out-Null}catch{$rejected=$true};Assert $rejected 'Expected refusal.'}
function Case($name,[scriptblock]$body){try{& $body;$cases.Add(@{name=$name;status='passed'})}catch{$cases.Add(@{name=$name;status='failed';reason=$_.Exception.Message})}}
$source=Join-Path $fixture 'project';$runtime=Join-Path $fixture 'runtime'
New-Item -ItemType Directory -Force -Path $runtime|Out-Null
Put (Join-Path $source 'src\AGENTS.md') 'new agents'
Put (Join-Path $source 'src\scripts\example.ps1') "'valid'"
Put (Join-Path $source 'src\adapters\knowledge-gate\optional.json') '{}'
Put (Join-Path $runtime 'AGENTS.md') 'old agents'
Case 'install-has-validated-retained-stage-and-optional-is-excluded' {
    $script:install=& $sync -ProjectRoot $source -GeminiHome $runtime | ConvertFrom-Json
    Assert (Test-Path -LiteralPath (Join-Path $install.backup 'stage\scripts\example.ps1')) 'Validated stage not retained.'
    Assert (-not(Test-Path -LiteralPath (Join-Path $runtime 'adapters'))) 'Optional adapter was globally installed.'
}
Case 'rollback-retains-new-files-and-restores-old' {
    & $sync -GeminiHome $runtime -RollbackManifest $install.transaction_manifest | Out-Null
    Assert ((Get-Content -LiteralPath (Join-Path $runtime 'AGENTS.md') -Raw) -eq 'old agents') 'Old file not restored.'
    Assert (-not(Test-Path -LiteralPath (Join-Path $runtime 'scripts\example.ps1'))) 'New file still active.'
    $retained=@(Get-ChildItem -LiteralPath (Join-Path $install.backup 'displaced') -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq 'example.ps1'})
    Assert ($retained.Count -gt 0) 'Rollback permanently removed newly installed file.'
}
Case 'invalid-source-is-refused-before-runtime-write' {
    Put (Join-Path $source 'src\scripts\example.ps1') 'function {'
    Reject { & $sync -ProjectRoot $source -GeminiHome $runtime }
    Assert ((Get-Content -LiteralPath (Join-Path $runtime 'AGENTS.md') -Raw) -eq 'old agents') 'Invalid stage partially installed.'
    Put (Join-Path $source 'src\scripts\example.ps1') "'valid'"
}
Case 'no-backup-unsafe-mode-refused' {Reject { & $sync -ProjectRoot $source -GeminiHome $runtime -NoBackup }}
Case 'manifest-target-private-path-forgery-refused' {
    $r=& $sync -ProjectRoot $source -GeminiHome $runtime|ConvertFrom-Json
    $m=Get-Content -LiteralPath $r.transaction_manifest -Raw|ConvertFrom-Json
    $original=[string]$m.files[0].relative_path;$m.files[0].relative_path='config.json'
    Put $r.transaction_manifest ($m|ConvertTo-Json -Depth 15)
    Reject {& $sync -GeminiHome $runtime -RollbackManifest $r.transaction_manifest}
    $m.files[0].relative_path=$original;Put $r.transaction_manifest ($m|ConvertTo-Json -Depth 15)
}
Case 'manifest-backup-traversal-refused' {
    $r=& $sync -ProjectRoot $source -GeminiHome $runtime|ConvertFrom-Json
    $m=Get-Content -LiteralPath $r.transaction_manifest -Raw|ConvertFrom-Json
    $old=$m.files[0].backup_relative_path;$m.files[0].backup_relative_path='..\AGENTS.md'
    Put $r.transaction_manifest ($m|ConvertTo-Json -Depth 15)
    Reject {& $sync -GeminiHome $runtime -RollbackManifest $r.transaction_manifest}
    $m.files[0].backup_relative_path=$old;Put $r.transaction_manifest ($m|ConvertTo-Json -Depth 15)
}
Case 'external-manifest-location-refused' {
    $r=& $sync -ProjectRoot $source -GeminiHome $runtime|ConvertFrom-Json
    $external=Join-Path $fixture 'external\sync-transaction.json';Put $external (Get-Content -LiteralPath $r.transaction_manifest -Raw)
    Copy-Item -LiteralPath (Join-Path $r.backup 'files') -Destination (Join-Path $fixture 'external\files') -Recurse
    Reject {& $sync -GeminiHome $runtime -RollbackManifest $external}
}
Case 'runtime-root-junction-refused' {
    $link=Join-Path $fixture 'runtime-link';New-Item -ItemType Junction -Path $link -Target $runtime|Out-Null
    Reject {& $sync -ProjectRoot $source -GeminiHome $link -DryRun}
}
Case 'mid-install-failure-recovers-and-retains-candidate' {
    $isolated=Join-Path $fixture 'fault-runtime';New-Item -ItemType Directory -Path $isolated|Out-Null
    Put (Join-Path $isolated 'AGENTS.md') 'fault old agents'
    Reject {& $sync -ProjectRoot $source -GeminiHome $isolated -TestFailAfterFiles 1}
    Assert ((Get-Content -LiteralPath (Join-Path $isolated 'AGENTS.md') -Raw) -eq 'fault old agents') 'Mid-install failure did not recover old file.'
    $journals=@(Get-ChildItem -LiteralPath $isolated -Recurse -Filter 'sync-transaction.json' -File)
    Assert ($journals.Count -eq 1) 'Fault journal missing.'
    $journal=Get-Content -LiteralPath $journals[0].FullName -Raw|ConvertFrom-Json
    Assert ($journal.status -eq 'rolled-back') 'Fault did not reach recovered transaction status.'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $journals[0].DirectoryName 'displaced') -Recurse -File).Count -gt 0) 'Failed candidate not retained.'
}
$failed=@($cases|Where-Object {$_.status -eq 'failed'}).Count
Case 'runtime-root-private-marker-refused' {
    $private=Join-Path $fixture 'root-private';New-Item -ItemType Directory -Path $private|Out-Null
    Put (Join-Path $private '.gemini-private') '';Put (Join-Path $private 'AGENTS.md') 'private original'
    Reject {& $sync -ProjectRoot $source -GeminiHome $private -DryRun}
    Assert ((Get-Content -LiteralPath (Join-Path $private 'AGENTS.md') -Raw) -eq 'private original') 'Private root changed.'
}
Case 'root-private-marker-blocks-rollback' {
    $private=Join-Path $fixture 'rollback-private';New-Item -ItemType Directory -Path $private|Out-Null
    $r=& $sync -ProjectRoot $source -GeminiHome $private|ConvertFrom-Json
    Put (Join-Path $private '.gemini-private') ''
    Reject {& $sync -GeminiHome $private -RollbackManifest $r.transaction_manifest}
}
$failed=@($cases|Where-Object {$_.status -eq 'failed'}).Count
Case 'source-hidden-stream-refused' {
    $adsSource=Join-Path $fixture 'ads-project';Put (Join-Path $adsSource 'src\AGENTS.md') 'visible fixture'
    Set-Content -LiteralPath (Join-Path $adsSource 'src\AGENTS.md') -Stream hidden -Value 'PRIVATE_FIXTURE_STREAM'
    Reject {& $sync -ProjectRoot $adsSource -GeminiHome $runtime -DryRun}
}
$failed=@($cases|Where-Object {$_.status -eq 'failed'}).Count
$report=@{status=if($failed){'failed'}else{'passed'};cases=$cases.Count;failed=$failed;results=@($cases.ToArray());fixture_root=$fixture;powershell=$PSVersionTable.PSVersion.ToString();coverage='Requirement cases; code coverage and live host unmeasured.'}
if($EvidencePath){Put $EvidencePath ($report|ConvertTo-Json -Depth 12)}
$report|ConvertTo-Json -Depth 12
if($failed){throw "$failed runtime sync cases failed."}
