param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$ContractPath,
    [Parameter(Mandatory = $true)][string]$EnvelopePath,
    [Parameter(Mandatory = $true)][string]$LedgerPath,
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$TestResultPath,
    [Parameter(Mandatory = $true)][string[]]$AcceptanceCriterionIds,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ClaimSummary,
    [ValidateSet('maker','test-author','test-runner','reviewer','human','completion-gate')][string]$ActorRole = 'maker',
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ActorId,
    [ValidateSet('planned','attempted','executed','partial','passed','checking','unverified','blocked')][string]$RequestedStatus = 'checking',
    [ValidateSet('maker','test-author','test-runner','reviewer','human','completion-gate')][string]$CheckerRole = 'reviewer',
    [switch]$CheckerIndependent,
    [string[]]$RemainingUncertainty = @(),
    [string]$ClaimId = "",
    [string]$OutputPath = "",
    [string]$PreviousClaimPath = '',
    [string]$PreviousDecisionPath = '',
    [string[]]$ToolOperationPaths = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
function Get-TextHash([string]$Text) { $sha=[Security.Cryptography.SHA256]::Create(); try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()} }
function Resolve-InRoot([string]$Root,[string]$Path) { $r=Get-AgPath $Root; $p=Get-AgPath $Path $r; if(-not $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Path is outside ProjectRoot.'}; $p }
function Relative([string]$Root,[string]$Path) { $r=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar; ([IO.Path]::GetFullPath($Path).Substring($r.Length)).Replace('\','/') }

try {
    $root=(Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
    $contractFull=Resolve-InRoot $root $ContractPath; $envelopeFull=Resolve-InRoot $root $EnvelopePath; $ledgerFull=Resolve-InRoot $root $LedgerPath; $reportFull=Resolve-InRoot $root $ReportPath; $testFull=Resolve-InRoot $root $TestResultPath
    foreach($p in @($contractFull,$envelopeFull,$ledgerFull,$reportFull,$testFull)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Required evidence is missing: $p"}}
    $contract=Get-Content -LiteralPath $contractFull -Raw -Encoding UTF8|ConvertFrom-Json
    $envelope=Get-Content -LiteralPath $envelopeFull -Raw -Encoding UTF8|ConvertFrom-Json
    $testResult=Get-Content -LiteralPath $testFull -Raw -Encoding UTF8|ConvertFrom-Json
    $ledger=Get-Content -LiteralPath $ledgerFull -Raw -Encoding UTF8|ConvertFrom-Json
    if($envelope.schema -ne 'antigravity-verification-envelope-v2' -or $envelope.status -ne 'passed'){throw 'Envelope is not a passed canonical verification envelope.'}
    if($testResult.schema -ne 'antigravity-test-result-v1'){throw 'Structured test result schema is invalid.'}
    $passedIds=@($testResult.cases|Where-Object {$_.status -eq 'passed'}|ForEach-Object {[string]$_.id})
    foreach($id in $AcceptanceCriterionIds){if($id -notin $passedIds){throw "Acceptance criterion is not passed in the structured test result: $id"};if($id -notin @($envelope.acceptance_criteria)){throw "Acceptance criterion is not covered by the envelope: $id"}}
    if(-not $ClaimId){$ClaimId='claim-'+(Get-Date).ToString('yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)}
    if(-not $OutputPath){$OutputPath=Join-Path $root ("artifacts\claims\$ClaimId.json")}
    $outputFull=Resolve-InRoot $root $OutputPath
    if(Test-Path -LiteralPath $outputFull){throw 'Claim output already exists; preserve the prior claim and select a new ClaimId.'}
    $envelopeHash=(Get-FileHash -LiteralPath $envelopeFull -Algorithm SHA256).Hash.ToLowerInvariant()
    $claim=[ordered]@{
      schema='antigravity-completion-claim-v1';producer_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();claim_id=$ClaimId;objective_sha256=Get-TextHash ([string]$contract.objective);claim_summary=$ClaimSummary.Trim();actor=[ordered]@{role=$ActorRole;id_sha256=Get-TextHash $ActorId};requested_status=$RequestedStatus;verification=[ordered]@{envelope_path=Relative $root $envelopeFull;envelope_sha256=$envelopeHash};attempt_history=[ordered]@{ledger_path=Relative $root $ledgerFull;ledger_sha256=(Get-FileHash $ledgerFull -Algorithm SHA256).Hash.ToLowerInvariant();report_path=Relative $root $reportFull;report_sha256=(Get-FileHash $reportFull -Algorithm SHA256).Hash.ToLowerInvariant()};checker=[ordered]@{role=$CheckerRole;independent=[bool]$CheckerIndependent};acceptance_criteria=@($AcceptanceCriterionIds|ForEach-Object{[ordered]@{id=$_;status='passed';evidence_sha256=$envelopeHash}});remaining_uncertainty=@($RemainingUncertainty);created_at=(Get-Date).ToUniversalTime().ToString('o')
    }
    $claim.task_id=[string]$ledger.task_id
    $claim.task_attempt_id=[string](@($ledger.attempts|Sort-Object sequence)[-1].attempt_id)
    $claim.contract=[ordered]@{path=Relative $root $contractFull;sha256=(Get-FileHash -LiteralPath $contractFull -Algorithm SHA256).Hash.ToLowerInvariant();contract_id=[string]$contract.contract_id}
    $claim.test_result=[ordered]@{path=Relative $root $testFull;sha256=(Get-FileHash -LiteralPath $testFull -Algorithm SHA256).Hash.ToLowerInvariant();run_id=[string]$envelope.id}
    $claim.repair_of=@()
    $claim.tool_operations=@()
    foreach($operationPath in $ToolOperationPaths){
        $operationFull=Get-AgPath $operationPath $root
        if(-not (Test-AgWithin $operationFull $root)){
            $eventRoot=Get-AgPath ((Get-AgRoots).events)
            if(-not (Test-AgWithin $operationFull $eventRoot) -or -not(Test-Path -LiteralPath (Join-Path $eventRoot '.gemini-private'))){throw 'Operation outside task or configured private event root.'}
        }
        $operation=Read-AgJson $operationFull;Assert-AgOperation $operation
        $reference=if(Test-AgWithin $operationFull $root){Relative $root $operationFull}else{$operationFull}
        $claim.tool_operations+=@([ordered]@{path=$reference;sha256=Get-AgFileHash $operationFull;operation_id=$operation.operation_id;task_id_sha256=$operation.task_id_sha256;attempt_id_sha256=$operation.attempt_id_sha256})
    }
    $claim.operation_coverage=if($claim.tool_operations.Count){'explicit_subset'}else{'not_supplied'}
    foreach($previous in @(@{kind='claim';path=$PreviousClaimPath},@{kind='decision';path=$PreviousDecisionPath})){if($previous.path){$priorFull=Resolve-InRoot $root $previous.path;$claim.repair_of+=@([ordered]@{kind=$previous.kind;path=Relative $root $priorFull;sha256=(Get-FileHash -LiteralPath $priorFull -Algorithm SHA256).Hash.ToLowerInvariant()})}}
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFull)|Out-Null
    $null=Resolve-InRoot $root $outputFull
    $bytes=[Text.Encoding]::UTF8.GetBytes(($claim|ConvertTo-Json -Depth 12));$stream=[IO.File]::Open($outputFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    [ordered]@{status='success';claim=$outputFull;claim_sha256=(Get-FileHash $outputFull -Algorithm SHA256).Hash.ToLowerInvariant()}|ConvertTo-Json -Compress
} catch { [ordered]@{status='error';error_code='completion_claim_creation_failed';error=$_.Exception.Message}|ConvertTo-Json -Compress }
