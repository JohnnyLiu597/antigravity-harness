param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}
$gate = Get-Content -LiteralPath (Join-Path $ProjectRoot "src\scripts\invoke-verification-gate.ps1") -Raw -Encoding UTF8
foreach ($required in @("run-harness-evals.ps1", "SkipBehavioralEvals", "behavioral-evals")) {
    if ($gate -notmatch [regex]::Escape($required)) {
        throw "Verification gate is missing v2 behavioral owner: $required"
    }
}
[ordered]@{ status = "success"; summary = "Verification gate invokes the behavioral eval owner once." } | ConvertTo-Json -Compress
