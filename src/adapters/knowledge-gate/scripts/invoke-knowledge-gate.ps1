param([Parameter(Mandatory=$true)][string]$FixtureRoot,[switch]$NoThrow)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'knowledge-common.ps1')
$root=(Resolve-Path -LiteralPath $FixtureRoot).Path
$issues=New-Object 'System.Collections.Generic.List[object]'
$observed=New-Object 'System.Collections.Generic.List[object]'
$hashes=New-Object 'System.Collections.Generic.List[object]'
$data=@{}; $task='unknown'
function Issue([string]$code,[string]$reference='', [string]$severity='error') {$issues.Add(@{code=$code;reference=$reference;severity=$severity})}
try {
    foreach($name in @('source-manifest','parser-observations','claim-ledger','verifier-results','critic-results','final-claims')) {
        $path=Resolve-KnowledgePath $root ($name+'.json')
        try {
            $data[$name]=[IO.File]::ReadAllText($path)|ConvertFrom-Json
            $schema=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot ('../schemas/'+$name+'.schema.json'))|ConvertFrom-Json
            Test-KnowledgeSchema $data[$name] $schema
        } catch {Issue 'schema_invalid' $name; continue}
        $hashes.Add(@{artifact=$name+'.json';sha256=(Get-KnowledgeHash $path)})
    }
    if($issues.Count -eq 0) {
        $task=$data['source-manifest'].task_id
        foreach($name in $data.Keys){if($data[$name].task_id -cne $task){Issue 'task_mismatch' $name}}
        $sources=@($data['source-manifest'].sources);$parser=$data['parser-observations'];$claims=@($data['claim-ledger'].claims);$verifier=@($data['verifier-results'].results);$final=$data['final-claims']
        foreach($group in @($sources|Group-Object id)){if($group.Count -ne 1){Issue 'duplicate_source_id' $group.Name}}
        foreach($group in @($claims|Group-Object id)){if($group.Count -ne 1){Issue 'duplicate_claim_id' $group.Name}}
        if(@($sources.id|Sort-Object) -join '|' -cne (@($parser.input_source_ids|Sort-Object) -join '|')){Issue 'parser_input_mismatch'}
        foreach($source in $sources) {
            try {$original=Resolve-KnowledgePath $root $source.path;$actual=Get-KnowledgeHash $original} catch {Issue $(if($_.Exception.Message -eq 'unsafe_path'){'unsafe_path'}else{'source_missing'}) $source.id;continue}
            $observed.Add(@{source_id=$source.id;expected_sha256=$source.expected_sha256;independently_observed_sha256=$actual})
            if($actual -cne $source.expected_sha256.ToLowerInvariant()){Issue 'source_hash_mismatch' $source.id}
            $obs=@($parser.observations|Where-Object {$_.source_id -ceq $source.id})
            if($obs.Count -ne 1){Issue 'observation_missing_or_duplicate' $source.id;continue};$o=$obs[0]
            if($actual -cne $o.observed_sha256.ToLowerInvariant()){Issue 'observed_hash_mismatch' $source.id}
            if(-not $o.original_read -or $o.capability -eq 'unavailable' -or ($source.media_type -ne 'text' -and $o.capability -ne 'native_multimodal')){Issue 'native_multimodal_unavailable' $source.id 'blocked'}
            if($o.full_coverage -and (-not $source.duration_reliable -or $null -eq $source.duration_seconds)){Issue 'unknown_duration_coverage' $source.id}
            foreach($time in @($o.timestamps)){if($source.duration_reliable -and $null -ne $source.duration_seconds -and $time -gt $source.duration_seconds){Issue 'timestamp_out_of_range' $source.id}}
            if($o.complete_transcript){try{[void](Resolve-KnowledgePath $root $o.transcript_path)}catch{Issue 'transcript_missing' $source.id}}
        }
        foreach($o in @($parser.observations)){if($o.source_id -cnotin @($sources.id)){Issue 'observation_unknown_source' $o.source_id}}
        foreach($claim in $claims) {
            if($claim.source_id -cnotin @($sources.id)){Issue 'claim_unknown_source' $claim.id}
            if($claim.external_truth -eq 'verified'){Issue 'external_truth_authority_unavailable' $claim.id}
            foreach($match in [regex]::Matches($claim.text,'(!?)\[\[([^\]]+)\]\]')) {
                $ref=($match.Groups[2].Value -split '[|#]')[0]
                $attachment=$match.Groups[1].Value -eq '!'
                try{[void](Resolve-KnowledgePath $root $(if($attachment){$ref}elseif($ref.EndsWith('.md')){$ref}else{$ref+'.md'}))}catch{Issue $(if($attachment){'attachment_missing'}else{'wiki_link_missing'}) $claim.id}
            }
            $checks=@($verifier|Where-Object {$_.claim_id -ceq $claim.id})
            if($checks.Count -gt 1){Issue 'duplicate_verifier' $claim.id}
            if((@($checks|Where-Object {$_.outcome -eq 'uncertain'}).Count -gt 0 -or $claim.source_fidelity -eq 'uncertain') -and ($claim.status -ne 'downgraded' -or $claim.source_fidelity -ne 'uncertain')){Issue 'uncertain_claim_not_downgraded' $claim.id}
            if($claim.id -cin @($final.claim_ids) -and (Test-KnowledgeRetiredText $claim.text $claims)){Issue 'stale_claim_wording' $claim.id}
            if($claim.risk -ne 'low') {
                if($checks.Count -ne 1){Issue 'high_risk_verifier_missing' $claim.id}
                # Evidence paths alone cannot prove independent authority. No high-risk action/publication promotion.
                if($claim.actionable -or $final.publication_status -eq 'publishable'){Issue 'high_risk_action_restricted' $claim.id}
                if($checks.Count -eq 1 -and $checks[0].outcome -eq 'supported' -and @($checks[0].evidence_paths).Count -eq 0){Issue 'verifier_evidence_missing' $claim.id}
            }
        }
        foreach($check in $verifier) {
            if($check.claim_id -cnotin @($claims.id)){Issue 'invalid_verifier_claim' $check.claim_id}
            foreach($p in @($check.evidence_paths)+@($check.external_evidence_paths)){try{[void](Resolve-KnowledgePath $root $p)}catch{Issue 'verifier_evidence_missing' $check.claim_id}}
        }
        foreach($finding in @($data['critic-results'].findings)) {
            if($finding.claim_id -cnotin @($claims.id)){Issue 'invalid_critic_claim' $finding.id}
            if(($finding.kind -ne 'reasoning' -or $finding.text -match '\d') -and @($finding.evidence_paths).Count -eq 0){Issue 'critic_evidence_missing' $finding.id}
            foreach($p in @($finding.evidence_paths)){try{[void](Resolve-KnowledgePath $root $p)}catch{Issue 'critic_evidence_missing' $finding.id}}
        }
        foreach($id in @($final.claim_ids)) {
            $c=@($claims|Where-Object {$_.id -ceq $id})
            if($c.Count -ne 1 -or $c[0].status -eq 'rejected' -or $c[0].source_fidelity -eq 'unsupported'){Issue 'invalid_final_claim' $id}
            $checks=@($verifier|Where-Object {$_.claim_id -ceq $id})
            if(@($checks|Where-Object {$_.outcome -eq 'unsupported'}).Count){Issue 'invalid_final_claim' $id}
        }
        if(@($final.claim_ids|Select-Object -Unique).Count -ne @($final.claim_ids).Count){Issue 'duplicate_final_claim'}
        foreach($kind in @('body','card','diagram')){if(@($final.surfaces|Where-Object {$_.kind -ceq $kind}).Count -ne 1){Issue 'missing_or_duplicate_surface' $kind}}
        foreach($link in @($final.wiki_links)){try{[void](Resolve-KnowledgePath $root ($link+'.md'))}catch{Issue 'wiki_link_missing' $link}}
        foreach($attachment in @($final.attachments)){try{[void](Resolve-KnowledgePath $root $attachment)}catch{Issue 'attachment_missing' $attachment}}
        $completed=[DateTimeOffset]::MinValue
        if(-not [DateTimeOffset]::TryParse($final.completed_at,[ref]$completed) -or $completed -gt [DateTimeOffset]::UtcNow){Issue 'completion_time_invalid'}
        foreach($input in @($hashes.ToArray())|Where-Object {$_.artifact -ne 'final-claims.json'}) {
            $p=Resolve-KnowledgePath $root $input.artifact
            if((Get-Item -LiteralPath $p).LastWriteTimeUtc -gt $completed.UtcDateTime){Issue 'input_modified_after_completion' $input.artifact}
        }
        foreach($source in $sources){try{$p=Resolve-KnowledgePath $root $source.path;if((Get-Item -LiteralPath $p).LastWriteTimeUtc -gt $completed.UtcDateTime){Issue 'input_modified_after_completion' $source.id}}catch{}}
        foreach($surface in @($final.surfaces)) {
            if((@($surface.claim_ids|Sort-Object) -join '|') -cne (@($final.claim_ids|Sort-Object) -join '|')){Issue 'surface_claim_set_mismatch' $surface.kind;continue}
            try {
                $p=Resolve-KnowledgePath $root $surface.path
                $actual=[IO.File]::ReadAllText($p).Replace("`r`n","`n")
                if(Test-KnowledgeRetiredText $actual $claims){Issue 'stale_claim_wording' $surface.kind}
                $expected=Get-KnowledgeSurfaceText $final $claims $surface
                if($actual -cne $expected){Issue 'surface_not_canonical' $surface.kind}
                if((Get-Item -LiteralPath $p).LastWriteTimeUtc -gt $completed.UtcDateTime){Issue 'modified_after_completion' $surface.kind}
            }catch{Issue 'surface_not_canonical' $surface.kind}
        }
    }
} catch {Issue $(if($_.Exception.Message -eq 'unsafe_path'){'unsafe_path'}else{'missing_or_invalid_artifact'})}
$errors=@($issues|Where-Object {$_.severity -eq 'error'}).Count
$blocked=@($issues|Where-Object {$_.severity -eq 'blocked'}).Count
$result=[ordered]@{schema_version='4.0';task_id=$task;status=$(if($errors){'failed'}elseif($blocked){'blocked'}else{'checking'});mechanical_checks=$(if($errors){'failed'}else{'passed'});semantic_verification=$(if($blocked){'blocked'}else{'unverified'});trusted_external_authority='unavailable';generated_at=[DateTime]::UtcNow.ToString('o');input_hashes=@($hashes.ToArray());source_observations=@($observed.ToArray());issues=@($issues.ToArray())}
$json=$result|ConvertTo-Json -Depth 20
$output=Resolve-KnowledgePath $root 'test-result.json' -AllowMissing
# Prior decisions are retained, including failed/blocked runs.
if(Test-Path -LiteralPath $output){$history=Resolve-KnowledgePath $root ('test-result.'+[guid]::NewGuid().ToString('N')+'.json') -AllowMissing;[IO.File]::Copy($output,$history,$false)}
[IO.File]::WriteAllText($output,$json,(New-Object Text.UTF8Encoding($false)))
$json
if($result.status -eq 'failed' -and -not $NoThrow){throw 'Knowledge Gate failed; inspect test-result.json'}
