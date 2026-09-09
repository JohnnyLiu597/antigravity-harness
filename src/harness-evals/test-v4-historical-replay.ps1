param([string]$ProjectRoot='')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
$fixture=Get-Content -LiteralPath (Join-Path $ProjectRoot 'tests\fixtures\v351\case02.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA ('Temp\ag-v4-replay-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
[IO.File]::WriteAllText((Join-Path $root '.gemini-private'),'')
foreach($record in $fixture.records){$dir=Join-Path $root ('correlations\'+$record.phase);New-Item -ItemType Directory -Path $dir -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $dir ($record.data.correlation_id_sha256+'.json')),($record.data|ConvertTo-Json -Depth 14))}
$audit=&(Join-Path $ProjectRoot 'src\scripts\audit-desktop-hook-session.ps1') -StateRoot $root -ConversationId $fixture.conversation_id|ConvertFrom-Json
if($audit.pre_count -ne 3 -or $audit.post_count -ne 1 -or $audit.denied_count -ne 2 -or $audit.missing_post_count -ne 0 -or $audit.orphan_post_count -ne 0 -or $audit.status -ne 'success'){throw 'Historical replay mismatch'}
$out=Join-Path $ProjectRoot ('artifacts\v4\replay-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'.json');New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force|Out-Null
[IO.File]::WriteAllText($out,(@{schema='antigravity-v4-replay-result';status='passed';original_modified=$false;fixture=$root;audit=$audit}|ConvertTo-Json -Depth 12))
@{status='passed';report=$out}|ConvertTo-Json -Compress
