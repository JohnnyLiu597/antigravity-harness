param([Parameter(Mandatory=$true)][string]$FixtureRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'knowledge-common.ps1')
$root=(Resolve-Path -LiteralPath $FixtureRoot).Path
$finalPath=Resolve-KnowledgePath $root 'final-claims.json'
$final=Get-Content -Raw -LiteralPath $finalPath|ConvertFrom-Json
$ledger=Get-Content -Raw -LiteralPath (Resolve-KnowledgePath $root 'claim-ledger.json')|ConvertFrom-Json
$manifest=Get-Content -Raw -LiteralPath (Resolve-KnowledgePath $root 'source-manifest.json')|ConvertFrom-Json
$verifier=Get-Content -Raw -LiteralPath (Resolve-KnowledgePath $root 'verifier-results.json')|ConvertFrom-Json
$parser=Get-Content -Raw -LiteralPath (Resolve-KnowledgePath $root 'parser-observations.json')|ConvertFrom-Json
$critic=Get-Content -Raw -LiteralPath (Resolve-KnowledgePath $root 'critic-results.json')|ConvertFrom-Json
$protected=@($manifest.sources.path)+@($final.attachments)+@($verifier.results.evidence_paths)+@($verifier.results.external_evidence_paths)+@($critic.findings.evidence_paths)+@($parser.observations.transcript_path)+@($final.wiki_links|ForEach-Object {$_+'.md'})
$protectedPaths=@()
foreach($relative in $protected){foreach($p in @($relative)){if($p){$protectedPaths+=Resolve-KnowledgePath $root $p -AllowMissing}}}
foreach($name in @('final-claims','claim-ledger')){
    $value=$(if($name -eq 'final-claims'){$final}else{$ledger})
    Test-KnowledgeSchema $value (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot ('../schemas/'+$name+'.schema.json'))|ConvertFrom-Json)
}
$targets=@()
foreach($surface in @($final.surfaces)) {
    $output=Resolve-KnowledgePath $root $surface.path -AllowMissing
    if([IO.Path]::GetExtension($output) -ine '.md' -or $output -iin $protectedPaths -or $output -iin @($targets.path)){throw 'Output path must be a distinct Markdown surface, never an original or evidence file'}
    if((@($surface.claim_ids|Sort-Object)-join '|') -cne (@($final.claim_ids|Sort-Object)-join '|')){throw 'surface_claim_set_mismatch'}
    foreach($id in @($surface.claim_ids)){if(@($ledger.claims|Where-Object {$_.id -ceq $id -and $_.status -ne 'rejected'}).Count -ne 1){throw 'invalid_final_claim'}}
    $targets+=@{path=$output;text=(Get-KnowledgeSurfaceText $final $ledger.claims $surface)}
}
foreach($target in $targets) {
    if(Test-Path -LiteralPath $target.path){[IO.File]::Copy($target.path,($target.path+'.'+[guid]::NewGuid().ToString('N')+'.previous'),$false)}
    [IO.File]::WriteAllText($target.path,$target.text,(New-Object Text.UTF8Encoding($false)))
}
[IO.File]::Copy($finalPath,($finalPath+'.'+[guid]::NewGuid().ToString('N')+'.previous'),$false)
$final.completed_at=[DateTime]::UtcNow.ToString('o')
[IO.File]::WriteAllText($finalPath,($final|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
@{status='rendered_not_verified';surfaces=$targets.Count}|ConvertTo-Json
