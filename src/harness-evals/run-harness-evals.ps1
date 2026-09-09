param(
    [string]$ProjectRoot = "",
    [ValidateRange(2,600)][int]$SuiteTimeoutSeconds=120
)

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Get-TextSha256 {
    param([AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$startedAt = Get-Date
$runId = $startedAt.ToString("yyyyMMdd-HHmmssfff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$runDir = Join-Path $ProjectRoot ("artifacts\harness-evals\runs\" + $runId)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$cases = @(
    [ordered]@{ id = "cross-engine-handoff"; script = "src\harness-evals\test-agent-handoff.ps1" },
    [ordered]@{ id = "strict-native-handoff"; script = "src\harness-evals\test-strict-handoff.ps1" },
    [ordered]@{ id = "modern-skill-discovery"; script = "deploy\test-modern-skills.ps1" },
    [ordered]@{ id = "truth-reset"; script = "src\harness-evals\test-truth-reset.ps1" },
    [ordered]@{ id = "control-plane"; script = "src\harness-evals\test-control-plane.ps1" },
    [ordered]@{ id = "attempt-ledger"; script = "src\harness-evals\test-attempt-ledger.ps1" },
    [ordered]@{ id = "execution-provenance"; script = "src\harness-evals\test-execution-provenance.ps1" },
    [ordered]@{ id = "verification-plane"; script = "src\harness-evals\test-verification-plane.ps1" },
    [ordered]@{ id = "governance-contracts"; script = "src\harness-evals\test-governance-contracts.ps1" },
    [ordered]@{ id = "package-integration"; script = "src\harness-evals\test-package-integration.ps1" },
    [ordered]@{ id = "gate-integration"; script = "src\harness-evals\test-gate-integration.ps1" },
    [ordered]@{ id = "project-scaffold-v2"; script = "src\harness-evals\test-project-scaffold-v2.ps1" },
    [ordered]@{ id = "getting-started-doc"; script = "tests\getting-started.tests.ps1" }
    [ordered]@{ id = "desktop-hook-probe"; script = "src\harness-evals\test-desktop-hook-probe.ps1" }
    [ordered]@{ id = "v4-control"; script = "src\harness-evals\test-v4-control.ps1" }
    [ordered]@{ id = "v4-policy"; script = "src\harness-evals\test-v4-policy.ps1" }
    [ordered]@{ id = "v4-completion"; script = "src\harness-evals\test-v4-completion.ps1" }
    [ordered]@{ id = "v4-knowledge"; script = "src\harness-evals\test-v4-knowledge.ps1" }
    [ordered]@{ id = "v4-deployment"; script = "src\harness-evals\test-v4-deployment.ps1" }
    [ordered]@{ id = "v4-runtime-sync"; script = "deploy\test-v4-runtime-sync.ps1" }
    [ordered]@{ id = "v4-historical-replay"; script = "src\harness-evals\test-v4-historical-replay.ps1" }
    [ordered]@{ id = "v4-installed-runtime"; script = "deploy\test-v4-installed-runtime.ps1" }
    [ordered]@{ id = "v4-runner"; script = "src\harness-evals\test-v4-runner.ps1" }
    [ordered]@{ id = "v4-runtime-import"; script = "deploy\test-v4-runtime-import.ps1" }
)

$results = New-Object System.Collections.Generic.List[object]
foreach ($case in $cases) {
    $caseStart = Get-Date
    $scriptPath = Join-Path $ProjectRoot $case.script
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $results.Add([pscustomobject]@{
            id = $case.id
            status = "failed"
            exit_code = $null
            duration_ms = 0
            output_sha256 = $null
            failure_class = "missing-test"
        }) | Out-Null
        continue
    }

    $exitCode=1;$output='';$timedOut=$false
    try {
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'" -ProjectRoot "'+$ProjectRoot+'"'
        $psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $timedOut=-not $process.WaitForExit($SuiteTimeoutSeconds*1000)
        if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;$process.WaitForExit(5000)|Out-Null}
        $exitCode=$process.ExitCode
        if($stdout.IsCompleted){$output+=$stdout.Result};if($stderr.IsCompleted){$output+=$stderr.Result}
    }catch{$exitCode=1;$output='suite_launch_or_capture_failed'}
    $results.Add([pscustomobject]@{
        id = $case.id
        status = if ($exitCode -eq 0 -and -not $timedOut) { "passed" } else { "failed" }
        exit_code = $exitCode
        duration_ms = [int]((Get-Date) - $caseStart).TotalMilliseconds
        output_sha256 = Get-TextSha256 -Value $output
        failure_class = if($timedOut){'suite-timeout'}elseif ($exitCode -eq 0) { $null } else { "test-failure" }
    }) | Out-Null
}

$failed = @($results | Where-Object { $_.status -ne "passed" })
$summary = [ordered]@{
    schema = "antigravity-harness-eval-run-v2"
    run_id = $runId
    status = if ($failed.Count -eq 0) { "passed" } else { "failed" }
    created_at = $startedAt.ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    duration_ms = [int]((Get-Date) - $startedAt).TotalMilliseconds
    counts = [ordered]@{ total = $results.Count; passed = $results.Count - $failed.Count; failed = $failed.Count }
    results = $results.ToArray()
}

$reportPath = Join-Path $runDir "summary.json"
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($reportPath, ($summary | ConvertTo-Json -Depth 8), $encoding)

$response = [ordered]@{
    status = if ($failed.Count -eq 0) { "success" } else { "failed" }
    summary = if ($failed.Count -eq 0) { "Antigravity harness behavioral regressions passed." } else { "Antigravity harness behavioral regressions failed." }
    report = $reportPath
    counts = $summary.counts
}

if ($failed.Count -gt 0) {
    $response | ConvertTo-Json -Depth 6 -Compress | Out-Host
    throw "Harness evals failed. See $reportPath"
}
$response | ConvertTo-Json -Depth 6 -Compress
