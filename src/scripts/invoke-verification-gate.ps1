param(
    [string]$ProjectRoot = ".",
    [switch]$SkipBoundaries,
    [switch]$SkipPackageCheck,
    [switch]$SkipBehavioralEvals
)

$ErrorActionPreference = "Stop"

$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$startedAt = Get-Date
$stamp = $startedAt.ToString("yyyyMMdd-HHmmss")
$runId = "$stamp-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$runDir = Join-Path $root ("artifacts\verification-gates\" + $runId)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$gateResults = New-Object System.Collections.Generic.List[object]
$overallPassed = $true

function Add-GateStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $stepStart = Get-Date
    $stepStatus = "passed"
    $stepDetail = ""

    try {
        $result = & $Action
        if ($null -ne $result) {
            $stepDetail = $result
        }
    } catch {
        $stepStatus = "failed"
        $stepDetail = $_.Exception.Message
        $script:overallPassed = $false
    }

    $durationMs = [int]((Get-Date) - $stepStart).TotalMilliseconds
    $gateResults.Add([pscustomobject]@{
        name = $Name
        status = $stepStatus
        duration_ms = $durationMs
        detail = $stepDetail
    }) | Out-Null
}

# 1. PowerShell Syntax Parsing
Add-GateStep -Name "powershell-syntax" -Action {
    $scripts = Get-ChildItem -Path $root -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notlike "*artifacts*" }
    $errors = @()
    foreach ($s in $scripts) {
        $parseErrors = $null
        [System.Management.Automation.PSParser]::Tokenize((Get-Content $s.FullName -Raw), [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0) {
            $errors += "$($s.Name): $($parseErrors[0].Message)"
        }
    }
    if ($errors.Count -gt 0) {
        throw ($errors -join "; ")
    }
    return "$($scripts.Count) scripts parsed cleanly"
}

# 2. JSON Validation
Add-GateStep -Name "json-validity" -Action {
    $jsons = Get-ChildItem -Path (Join-Path $root "src") -Recurse -Filter "*.json" -ErrorAction SilentlyContinue
    $errors = @()
    foreach ($j in $jsons) {
        try {
            Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        } catch {
            $errors += "$($j.Name): $($_.Exception.Message)"
        }
    }
    if ($errors.Count -gt 0) {
        throw ($errors -join "; ")
    }
    return "$($jsons.Count) JSON files valid"
}

# 3. Context Budget Audit
Add-GateStep -Name "context-budget" -Action {
    $auditScript = Join-Path $root "src\scripts\audit-context-budget.ps1"
    if (Test-Path -LiteralPath $auditScript) {
        $raw = & $auditScript -ProjectRoot $root
        $json = $raw | ConvertFrom-Json
        if ($json.status -ne "passed") {
            throw ($json.warnings -join "; ")
        }
        return "Total $($json.total_lines) lines across $($json.total_files) files within budget"
    }
    return "skipped: audit script missing"
}

# 4. Package Verification (deploy/verify-package.ps1)
if (-not $SkipPackageCheck) {
    Add-GateStep -Name "package-verification" -Action {
        $verifyScript = Join-Path $root "deploy\verify-package.ps1"
        if (Test-Path -LiteralPath $verifyScript) {
            $raw = & $verifyScript -ProjectRoot $root
            $json = $raw | ConvertFrom-Json
            if ($json.status -ne "success") {
                throw "Package verification failed"
            }
            return "Package verification passed"
        }
        return "skipped: verify-package.ps1 missing"
    }
}

# 5. Behavioral regression owner
if (-not $SkipBehavioralEvals) {
    Add-GateStep -Name "behavioral-evals" -Action {
        $evalScript = Join-Path $root "src\harness-evals\run-harness-evals.ps1"
        if (-not (Test-Path -LiteralPath $evalScript -PathType Leaf)) {
            throw "run-harness-evals.ps1 missing"
        }
        $raw = & $evalScript -ProjectRoot $root
        $json = $raw | ConvertFrom-Json
        if ($json.status -ne "success") {
            throw "Behavioral eval owner failed"
        }
        return "Behavioral evals passed: $($json.counts.passed)/$($json.counts.total)"
    }
}

# 6. Boundary Integration Tests (deploy/test-sync-boundaries.ps1)
if (-not $SkipBoundaries) {
    Add-GateStep -Name "sync-boundaries" -Action {
        $boundScript = Join-Path $root "deploy\test-sync-boundaries.ps1"
        if (Test-Path -LiteralPath $boundScript) {
            $raw = & $boundScript -ProjectRoot $root
            $json = $raw | ConvertFrom-Json
            if ($json.status -ne "success") {
                throw "Sync boundary tests failed"
            }
            return "Boundary tests passed"
        }
        return "skipped: test-sync-boundaries.ps1 missing"
    }
}

$summary = [ordered]@{
    schema = "antigravity-harness-verification-gate-v1"
    status = if ($overallPassed) { "passed" } else { "failed" }
    run_id = $runId
    project_root = $root
    duration_total_ms = [int]((Get-Date) - $startedAt).TotalMilliseconds
    steps = $gateResults.ToArray()
}

$reportPath = Join-Path $runDir "gate.json"
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if (-not $overallPassed) {
    $summary | ConvertTo-Json -Depth 5 -Compress | Out-Host
    throw "Verification gate failed. See $reportPath"
}

[ordered]@{
    status = "success"
    summary = "Verification gate passed."
    report = $reportPath
} | ConvertTo-Json -Depth 5 -Compress
