param([string]$ProjectRoot='')
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))}
$run=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$dir=Join-Path $ProjectRoot ('artifacts\v4\release-'+$run);New-Item -ItemType Directory -Path $dir -Force|Out-Null
$results=@()
foreach($relative in @('deploy\verify-package.ps1','deploy\test-sync-boundaries.ps1','src\harness-evals\run-harness-evals.ps1')){
 $start=[Diagnostics.Stopwatch]::StartNew();$p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName='powershell.exe';$p.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $ProjectRoot $relative)+'" -ProjectRoot "'+$ProjectRoot+'"';$p.UseShellExecute=$false;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($p);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
 $timedOut=-not $process.WaitForExit(600000)
 if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;$process.WaitForExit(5000)|Out-Null}
 $linkedReport=$null
 if($stdout.IsCompleted){foreach($line in ($stdout.Result -split '\r?\n')){if($line.TrimStart().StartsWith('{')){try{$value=$line|ConvertFrom-Json;if($value.PSObject.Properties.Name -contains 'report'){$linkedReport=[string]$value.report}}catch{}}}}
 $results+=@{test=$relative;status=if(-not $timedOut -and $process.ExitCode -eq 0){'passed'}else{'failed'};exit_code=$process.ExitCode;timed_out=$timedOut;duration_ms=$start.ElapsedMilliseconds;report=$linkedReport}
 Write-Host ($relative+': '+$results[-1].status)
}
$summary=@{schema='antigravity-v4-release-check-v1';run_id=$run;created_at=[DateTime]::UtcNow.ToString('o');results=$results;status=if(@($results|Where-Object status -eq 'failed').Count){'failed'}else{'passed'};live_desktop='pending';line_coverage='unmeasured'}
[IO.File]::WriteAllText((Join-Path $dir 'summary.json'),($summary|ConvertTo-Json -Depth 8))
@{status=$summary.status;report=(Join-Path $dir 'summary.json')}|ConvertTo-Json -Compress
if($summary.status -ne 'passed'){throw 'Release regression failed; preserve linked suite evidence.'}
