param([string]$ProjectRoot='')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
$root=Join-Path $env:TEMP ('antigravity-runner-test-'+[guid]::NewGuid().ToString('N'));$scripts=Join-Path $root 'src\harness-evals';New-Item -ItemType Directory -Path $scripts -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $scripts 'test-truth-reset.ps1'),"[Console]::Error.WriteLine('PRIVATE_RAW_TEST_ERROR'); exit 1")
$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $ProjectRoot 'src\harness-evals\run-harness-evals.ps1')+'" -ProjectRoot "'+$root+'"';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$p=[Diagnostics.Process]::Start($psi);$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(20000)){$p.Kill();throw 'runner test timeout'}
$reports=@(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts\harness-evals\runs') -Recurse -Filter summary.json -ErrorAction SilentlyContinue)
if($p.ExitCode -eq 0 -or $reports.Count -ne 1){throw 'Failed child must leave a structured aggregate summary, not abort on stderr.'}
$text=[IO.File]::ReadAllText($reports[0].FullName);$r=$text|ConvertFrom-Json
if($r.status -ne 'failed' -or $r.results[0].status -ne 'failed' -or $r.results.Count -lt 18 -or $text.Contains('PRIVATE_RAW_TEST_ERROR')){throw 'Failure aggregation/privacy invalid'}
@{status='success';case='child-stderr-failure-aggregated-without-raw-output';fixture=$root}|ConvertTo-Json -Compress
