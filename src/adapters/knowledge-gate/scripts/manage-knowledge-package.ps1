param([ValidateSet('Install','Diagnose','Rollback')][string]$Action='Diagnose',
    [Parameter(Mandatory=$true)][string]$FixtureRoot,
    [string]$TransactionId='', [ValidateSet('none','postcheck')][string]$FailAt='none')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'knowledge-common.ps1')
$root=(Resolve-Path -LiteralPath $FixtureRoot).Path
# Deliberately fixture-only. A real-vault installer is a separate authorization/change.
[void](Resolve-KnowledgePath $root '.knowledge-gate-fixture')
if(Test-Path -LiteralPath (Join-Path $root '.obsidian')){throw 'Real Obsidian installation is not authorized by this fixture installer'}
$active=Resolve-KnowledgePath $root '.knowledge-gate' -AllowMissing
$txRoot=Resolve-KnowledgePath $root '.knowledge-gate-transactions' -AllowMissing
New-Item -ItemType Directory -Path $txRoot -Force|Out-Null
$lockPath=Resolve-KnowledgePath $root '.knowledge-gate-transactions/install.lock' -AllowMissing
$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
function Check-Package([string]$candidate,$entries) {
    foreach($entry in $entries){$p=Resolve-KnowledgePath $candidate $entry.path;if((Get-KnowledgeHash $p) -cne $entry.sha256){throw 'Package hash check failed'}}
}
function Save-Transaction($path,$state) {[IO.File]::WriteAllText($path,($state|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))}
try {
    if($Action -eq 'Diagnose') {
        @{status=$(if(Test-Path -LiteralPath $active){'installed_unverified'}else{'not_installed'});scope='fixture_only'}|ConvertTo-Json;return
    }
    if($Action -eq 'Rollback') {
        if($TransactionId -cnotmatch '^[a-f0-9]{32}$'){throw 'An explicit transaction ID is required'}
        $tx=Resolve-KnowledgePath $root ('.knowledge-gate-transactions/'+$TransactionId)
        $journal=Resolve-KnowledgePath $root ('.knowledge-gate-transactions/'+$TransactionId+'/transaction.json')
        $state=Get-Content -Raw -LiteralPath $journal|ConvertFrom-Json
        if($state.transaction_id -cne $TransactionId -or $state.status -ne 'installed'){throw 'Transaction is not rollback eligible'}
        # Only the current installation may be rolled back; never pick a latest file by timestamp.
        $current=Get-Content -Raw -LiteralPath (Resolve-KnowledgePath $active 'installation.json')|ConvertFrom-Json
        if($current.transaction_id -cne $TransactionId){throw 'Transaction is not the current installation'}
        $retained=Resolve-KnowledgePath $root ('.knowledge-gate-transactions/'+$TransactionId+'/rolled-back-payload') -AllowMissing
        if(Test-Path -LiteralPath $retained){throw 'Rollback payload already exists'}
        $backup=Resolve-KnowledgePath $root ('.knowledge-gate-transactions/'+$TransactionId+'/previous') -AllowMissing
        Move-Item -LiteralPath $active -Destination $retained
        if(Test-Path -LiteralPath $backup){Move-Item -LiteralPath $backup -Destination $active}
        $state.status='rolled_back';Save-Transaction $journal $state
        @{status='rolled_back';transaction_id=$TransactionId;scope='fixture_only'}|ConvertTo-Json;return
    }
    $id=[guid]::NewGuid().ToString('N')
    $tx=Join-Path $txRoot $id;New-Item -ItemType Directory -Path $tx|Out-Null
    $stage=Join-Path $tx 'staging';New-Item -ItemType Directory -Path $stage|Out-Null
    $backup=Join-Path $tx 'previous';$journal=Join-Path $tx 'transaction.json'
    $source=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $entries=@()
    foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
        $rel=$file.FullName.Substring($source.Length).TrimStart('\','/').Replace('\','/')
        [void](Resolve-KnowledgePath $source $rel)
        $dest=Resolve-KnowledgePath $stage $rel -AllowMissing
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force|Out-Null
        [IO.File]::Copy($file.FullName,$dest,$false)
        $entries+=@{path=$rel;sha256=(Get-KnowledgeHash $file.FullName)}
    }
    Check-Package $stage $entries
    $state=@{transaction_id=$id;status='staged';entries=$entries};Save-Transaction $journal $state
    $movedOld=$false;$movedNew=$false
    try {
        if(Test-Path -LiteralPath $active){Move-Item -LiteralPath $active -Destination $backup;$movedOld=$true}
        Move-Item -LiteralPath $stage -Destination $active;$movedNew=$true
        if($FailAt -eq 'postcheck'){throw 'Injected post-install failure'}
        Check-Package $active $entries
        Save-Transaction (Join-Path $active 'installation.json') @{transaction_id=$id}
        $state.status='installed';Save-Transaction $journal $state
    } catch {
        if($movedNew){Move-Item -LiteralPath $active -Destination (Join-Path $tx 'failed-payload')}
        if($movedOld){Move-Item -LiteralPath $backup -Destination $active}
        $state.status='failed_recovered';Save-Transaction $journal $state
        throw
    }
    @{status='installed';transaction_id=$id;scope='fixture_only'}|ConvertTo-Json
} finally {$lock.Dispose()}
