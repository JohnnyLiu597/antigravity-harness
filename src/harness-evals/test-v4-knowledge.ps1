param([string]$ProjectRoot = '', [string]$EvidenceRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
if (-not $EvidenceRoot) {
    # Transaction staging appends nested package paths. Keep fixture depth
    # independent of the source checkout so Windows PowerShell/.NET File.Copy
    # does not hit MAX_PATH in a deeply nested isolated release candidate.
    $EvidenceRoot = Join-Path ([IO.Path]::GetTempPath()) ('ag-knowledge-' + [guid]::NewGuid().ToString('N').Substring(0,12))
}
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$package = Join-Path $ProjectRoot 'src/adapters/knowledge-gate'
$gate = Join-Path $package 'scripts/invoke-knowledge-gate.ps1'
$script:cases = @()
function Save-Json($path, $value) { [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false))) }
function New-Fixture($name) {
    $root = Join-Path $EvidenceRoot $name
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'original.txt'), 'The sample has two sections.')
    [IO.File]::WriteAllText((Join-Path $root 'Related.md'), '# Related')
    [IO.File]::WriteAllText((Join-Path $root 'attachment.txt'), 'fixture attachment')
    $hash = (Get-FileHash (Join-Path $root 'original.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = @{schema_version='4.0'; task_id='knowledge-fixture'; sources=@(@{id='s1'; path='original.txt'; media_type='text'; expected_sha256=$hash; duration_seconds=10; duration_reliable=$true})}
    $parser = @{schema_version='4.0'; task_id='knowledge-fixture'; input_source_ids=@('s1'); output_requirements=@('claims with evidence'); observations=@(@{source_id='s1'; observed_sha256=$hash; original_read=$true; capability='text'; full_coverage=$false; complete_transcript=$false; transcript_path=''; timestamps=@(0,5)})}
    $ledger = @{schema_version='4.0'; task_id='knowledge-fixture'; claims=@(@{id='c1'; source_id='s1'; text='The sample has two sections.'; source_fidelity='supported'; external_truth='not_checked'; risk='low'; actionable=$false; status='accepted'; previous_text=@()})}
    $verifier = @{schema_version='4.0'; task_id='knowledge-fixture'; results=@(@{claim_id='c1'; outcome='supported'; evidence_paths=@('original.txt'); external_evidence_paths=@()})}
    $critic = @{schema_version='4.0'; task_id='knowledge-fixture'; findings=@()}
    $final = @{schema_version='4.0'; task_id='knowledge-fixture'; claim_ids=@('c1'); publication_status='draft'; completed_at='2090-01-01T00:00:00Z'; required_sections=@('Summary'); wiki_links=@('Related'); attachments=@('attachment.txt'); surfaces=@(@{kind='body';path='body.md';claim_ids=@('c1')},@{kind='card';path='card.md';claim_ids=@('c1')},@{kind='diagram';path='diagram.md';claim_ids=@('c1')})}
    # Completion is deliberately in the near past; output files are timestamped before it.
    $final.completed_at = [DateTime]::UtcNow.AddSeconds(-1).ToString('o')
    foreach ($entry in @(@('source-manifest',$manifest),@('parser-observations',$parser),@('claim-ledger',$ledger),@('verifier-results',$verifier),@('critic-results',$critic),@('final-claims',$final))) { Save-Json (Join-Path $root ($entry[0]+'.json')) $entry[1] }
    $content = "## Summary`n<!-- claim:c1 -->`nThe sample has two sections.`n`n[[Related]]`n![[attachment.txt]]`n"
    foreach ($p in @('body.md','card.md','diagram.md')) { [IO.File]::WriteAllText((Join-Path $root $p),$content); (Get-Item (Join-Path $root $p)).LastWriteTimeUtc=[DateTime]::UtcNow.AddSeconds(-5) }
    foreach($item in Get-ChildItem -LiteralPath $root -File){$item.LastWriteTimeUtc=[DateTime]::UtcNow.AddSeconds(-5)}
    return $root
}
function Change-Json($root,$name,$change) { $p=Join-Path $root "$name.json";$time=(Get-Item $p).LastWriteTimeUtc;$v=Get-Content -Raw $p|ConvertFrom-Json; & $change $v; Save-Json $p $v;(Get-Item $p).LastWriteTimeUtc=$time }
function Case($name,$expected,$code,$mutate) {
    $root=New-Fixture $name
    try {
        & $mutate $root
        if (-not (Test-Path -LiteralPath $gate)) { throw 'Knowledge Gate implementation is missing' }
        $result = & $gate -FixtureRoot $root -NoThrow | ConvertFrom-Json
        if ($result.status -ne $expected -or ($code -and $code -notin @($result.issues.code))) { throw "Expected $expected/$code; got $($result.status)/$($result.issues.code -join ',')" }
        $script:cases += @{id=$name;status='passed';fixture=$name;observed_gate=$result.status}
    } catch { $script:cases += @{id=$name;status='failed';fixture=$name;error=$_.Exception.Message} }
}
Case 'valid-text' 'checking' '' { param($r) }
Case 'duration-overflow' 'failed' 'timestamp_out_of_range' { param($r) Change-Json $r 'parser-observations' {param($v) $v.observations[0].timestamps=@(11)} }
Case 'unknown-duration-coverage' 'failed' 'unknown_duration_coverage' { param($r) Change-Json $r 'source-manifest' {param($v) $v.sources[0].duration_reliable=$false}; Change-Json $r 'parser-observations' {param($v) $v.observations[0].full_coverage=$true} }
Case 'missing-transcript' 'failed' 'transcript_missing' { param($r) Change-Json $r 'parser-observations' {param($v) $v.observations[0].complete_transcript=$true} }
Case 'false-observed-hash' 'failed' 'observed_hash_mismatch' { param($r) Change-Json $r 'parser-observations' {param($v) $v.observations[0].observed_sha256=('0'*64)} }
Case 'copied-hashes-original-mutated' 'failed' 'source_hash_mismatch' { param($r) [IO.File]::WriteAllText((Join-Path $r 'original.txt'),'Changed original') }
Case 'truth-dimension-mixing' 'failed' 'external_truth_authority_unavailable' { param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].external_truth='verified'} }
Case 'parser-prefilled-conclusion' 'failed' 'schema_invalid' { param($r) Change-Json $r 'parser-observations' {param($v) $v|Add-Member NoteProperty expected_findings @('two sections')} }
Case 'high-risk-missing-verifier' 'failed' 'high_risk_verifier_missing' { param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].risk='financial'}; Change-Json $r 'verifier-results' {param($v) $v.results=@()} }
Case 'high-risk-uncertain-action' 'failed' 'high_risk_action_restricted' { param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].risk='legal';$v.claims[0].actionable=$true}; Change-Json $r 'verifier-results' {param($v) $v.results[0].outcome='uncertain'} }
Case 'critic-unsupported-number' 'failed' 'critic_evidence_missing' { param($r) Change-Json $r 'critic-results' {param($v) $v.findings=@(@{id='k1';claim_id='c1';kind='statistic';text='90% failed';evidence_paths=@()})} }
Case 'final-rejected-claim' 'failed' 'invalid_final_claim' { param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].status='rejected'} }
Case 'card-inconsistent-reference' 'failed' 'surface_claim_set_mismatch' { param($r) Change-Json $r 'final-claims' {param($v) $v.surfaces[1].claim_ids=@('old-claim')} }
Case 'downgraded-old-wording' 'failed' 'surface_not_canonical' { param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].text='The sample may have two sections.';$v.claims[0].previous_text=@('The sample has two sections.')} }
Case 'broken-wiki-link' 'failed' 'wiki_link_missing' { param($r) Change-Json $r 'final-claims' {param($v) $v.wiki_links=@('Missing')} }
Case 'missing-attachment' 'failed' 'attachment_missing' { param($r) Change-Json $r 'final-claims' {param($v) $v.attachments=@('Missing.png')} }
Case 'missing-section' 'failed' 'surface_not_canonical' { param($r) Change-Json $r 'final-claims' {param($v) $v.required_sections=@('Summary','Evidence')} }
Case 'modified-after-completion' 'failed' 'modified_after_completion' { param($r) (Get-Item (Join-Path $r 'body.md')).LastWriteTimeUtc=[DateTime]::UtcNow }
Case 'future-completion' 'failed' 'completion_time_invalid' { param($r) Change-Json $r 'final-claims' {param($v) $v.completed_at='2090-01-01T00:00:00Z'} }
Case 'cross-task-artifact' 'failed' 'task_mismatch' { param($r) Change-Json $r 'verifier-results' {param($v) $v.task_id='other-task'} }
Case 'escaping-original' 'failed' 'unsafe_path' { param($r) Change-Json $r 'source-manifest' {param($v) $v.sources[0].path='../outside.txt'} }
Case 'image-native-unavailable' 'blocked' 'native_multimodal_unavailable' { param($r) Change-Json $r 'source-manifest' {param($v) $v.sources[0].media_type='image'}; Change-Json $r 'parser-observations' {param($v) $v.observations[0].capability='unavailable';$v.observations[0].original_read=$false} }
Case 'video-native-unavailable' 'blocked' 'native_multimodal_unavailable' { param($r) Change-Json $r 'source-manifest' {param($v) $v.sources[0].media_type='video'}; Change-Json $r 'parser-observations' {param($v) $v.observations[0].capability='unavailable';$v.observations[0].original_read=$false}; Get-ChildItem -LiteralPath $r -File|ForEach-Object {$_.LastWriteTimeUtc=[DateTime]::UtcNow.AddSeconds(-5)} }
Case 'changed-input-after-completion' 'failed' 'input_modified_after_completion' {param($r) (Get-Item (Join-Path $r 'claim-ledger.json')).LastWriteTimeUtc=[DateTime]::UtcNow}
Case 'embedded-broken-wiki-link' 'failed' 'wiki_link_missing' {param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].text+=' [[HiddenMissing]]'}}
Case 'uncertain-high-risk-draft' 'checking' '' {param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].risk='financial';$v.claims[0].status='downgraded';$v.claims[0].source_fidelity='uncertain'};Change-Json $r 'verifier-results' {param($v) $v.results[0].outcome='uncertain'};& (Join-Path $package 'scripts/render-knowledge-surfaces.ps1') -FixtureRoot $r|Out-Null}
Case 'uncertain-verifier-with-certain-ledger' 'failed' 'uncertain_claim_not_downgraded' {param($r) Change-Json $r 'verifier-results' {param($v) $v.results[0].outcome='uncertain'}}
Case 'previous-wording-still-current' 'failed' 'stale_claim_wording' {param($r) Change-Json $r 'claim-ledger' {param($v) $v.claims[0].previous_text=@($v.claims[0].text)}}
try {
    $r=New-Fixture 'renderer-hardlink-original-protection'
    Move-Item -LiteralPath (Join-Path $r 'body.md') -Destination (Join-Path $r 'retained-body.md')
    New-Item -ItemType HardLink -Path (Join-Path $r 'body.md') -Target (Join-Path $r 'original.txt')|Out-Null
    $before=(Get-FileHash (Join-Path $r 'original.txt')).Hash;$rejected=$false
    try{& (Join-Path $package 'scripts/render-knowledge-surfaces.ps1') -FixtureRoot $r|Out-Null}catch{$rejected=$true}
    if(-not $rejected -or (Get-FileHash (Join-Path $r 'original.txt')).Hash -ne $before){throw 'Renderer overwrote hardlinked original'}
    $script:cases+=@{id='renderer-hardlink-original-protection';status='passed'}
}catch{$script:cases+=@{id='renderer-hardlink-original-protection';status='failed';error=$_.Exception.Message}}
try {
    $r=New-Fixture 'gate-result-hardlink-original-protection'
    New-Item -ItemType HardLink -Path (Join-Path $r 'test-result.json') -Target (Join-Path $r 'original.txt')|Out-Null
    $before=(Get-FileHash (Join-Path $r 'original.txt')).Hash;$rejected=$false
    try{& $gate -FixtureRoot $r -NoThrow|Out-Null}catch{$rejected=$true}
    if(-not $rejected -or (Get-FileHash (Join-Path $r 'original.txt')).Hash -ne $before){throw 'Gate overwrote hardlinked original'}
    $script:cases+=@{id='gate-result-hardlink-original-protection';status='passed'}
}catch{$script:cases+=@{id='gate-result-hardlink-original-protection';status='failed';error=$_.Exception.Message}}
try {
    $r=New-Fixture 'uncertain-canonical-visible'
    Change-Json $r 'claim-ledger' {param($v) $v.claims[0].status='downgraded';$v.claims[0].source_fidelity='uncertain'}
    Change-Json $r 'verifier-results' {param($v) $v.results[0].outcome='uncertain'}
    & (Join-Path $package 'scripts/render-knowledge-surfaces.ps1') -FixtureRoot $r|Out-Null
    foreach($surface in @('body.md','card.md','diagram.md')){if(-not ([IO.File]::ReadAllText((Join-Path $r $surface))).Contains('[Uncertain] ')){throw 'Uncertainty not visibly propagated'}}
    $script:cases+=@{id='uncertain-canonical-visible';status='passed'}
}catch{$script:cases+=@{id='uncertain-canonical-visible';status='failed';error=$_.Exception.Message}}
Case 'ads-original-denied' 'failed' 'unsafe_path' {param($r) Change-Json $r 'source-manifest' {param($v) $v.sources[0].path='original.txt:stream'}}
Case 'duplicate-source-id' 'failed' 'duplicate_source_id' {param($r) Change-Json $r 'source-manifest' {param($v) $v.sources=@($v.sources[0],$v.sources[0])}}
Case 'malformed-json-visible' 'failed' 'schema_invalid' {param($r) [IO.File]::WriteAllText((Join-Path $r 'critic-results.json'),'{broken')}
try {
    $r=New-Fixture 'schema-template-render-roundtrip'
    . (Join-Path $package 'scripts/knowledge-common.ps1')
    foreach($file in Get-ChildItem (Join-Path $package 'templates') -Filter '*.json') {
        Test-KnowledgeSchema (Get-Content -Raw $file.FullName|ConvertFrom-Json) (Get-Content -Raw (Join-Path $package ('schemas/'+$file.BaseName+'.schema.json'))|ConvertFrom-Json)
    }
    & (Join-Path $package 'scripts/render-knowledge-surfaces.ps1') -FixtureRoot $r|Out-Null
    $result=& $gate -FixtureRoot $r -NoThrow|ConvertFrom-Json
    Test-KnowledgeSchema $result (Get-Content -Raw (Join-Path $package 'schemas/test-result.schema.json')|ConvertFrom-Json)
    if($result.status -ne 'checking'){throw 'Rendered output failed gate'}
    $script:cases+=@{id='schema-template-render-roundtrip';status='passed'}
}catch{$script:cases+=@{id='schema-template-render-roundtrip';status='failed';error=$_.Exception.Message}}
try {
    $r=New-Fixture 'renderer-original-protection'
    Change-Json $r 'final-claims' {param($v) $v.surfaces[0].path='original.txt'}
    $before=(Get-FileHash (Join-Path $r 'original.txt')).Hash;$rejected=$false
    try{& (Join-Path $package 'scripts/render-knowledge-surfaces.ps1') -FixtureRoot $r|Out-Null}catch{$rejected=$true}
    if(-not $rejected -or (Get-FileHash (Join-Path $r 'original.txt')).Hash -ne $before){throw 'Renderer can overwrite original'}
    $script:cases+=@{id='renderer-original-protection';status='passed'}
}catch{$script:cases+=@{id='renderer-original-protection';status='failed';error=$_.Exception.Message}}
try {
    $install=Join-Path $package 'scripts/manage-knowledge-package.ps1'
    if(-not (Test-Path $install)){throw 'Knowledge package installer missing'}
    $target=Join-Path $EvidenceRoot 'install-fixture';New-Item -ItemType Directory -Path $target|Out-Null
    [IO.File]::WriteAllText((Join-Path $target '.knowledge-gate-fixture'),'isolated test fixture')
    $first=& $install -Action Install -FixtureRoot $target | ConvertFrom-Json
    if($first.status -ne 'installed'){throw 'first install failed'}
    $file=Join-Path $target '.knowledge-gate/scripts/knowledge-common.ps1';$before=(Get-FileHash $file).Hash
    try{& $install -Action Install -FixtureRoot $target -FailAt postcheck|Out-Null;throw 'fault was not injected'}catch{if($_.Exception.Message -eq 'fault was not injected'){throw}}
    if((Get-FileHash $file).Hash -ne $before){throw 'fault recovery altered installation'}
    $second=& $install -Action Install -FixtureRoot $target|ConvertFrom-Json
    $rollback=& $install -Action Rollback -FixtureRoot $target -TransactionId $second.transaction_id|ConvertFrom-Json
    if($rollback.status -ne 'rolled_back' -or (Get-FileHash $file).Hash -ne $before){throw 'rollback failed'}
    $script:cases+=@{id='package-install-failure-rollback';status='passed'}
}catch{$script:cases+=@{id='package-install-failure-rollback';status='failed';error=$_.Exception.Message}}
$failed=@($script:cases|Where-Object {$_.status -eq 'failed'})
$summary=@{schema_version='4.0';suite='knowledge-gate';status=$(if($failed.Count){'failed'}else{'passed'});passed=$script:cases.Count-$failed.Count;total=$script:cases.Count;cases=$script:cases;line_coverage='unmeasured';native_semantic_verification='blocked'}
Save-Json (Join-Path $EvidenceRoot 'summary.json') $summary
$summary|ConvertTo-Json -Depth 12
if($failed.Count){throw "$($failed.Count) Knowledge Gate cases failed; evidence retained at $EvidenceRoot"}
