param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path }
$audit = Join-Path $ProjectRoot "src\scripts\audit-governed-execution.ps1"
$newClaim = Join-Path $ProjectRoot "src\scripts\new-completion-claim.ps1"
if (-not (Test-Path -LiteralPath $audit -PathType Leaf)) { throw "Execution provenance audit is missing." }
if (-not (Test-Path -LiteralPath $newClaim -PathType Leaf)) { throw "Canonical completion claim producer is missing." }

function Write-JsonFile([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$tmp = Join-Path $env:TEMP ("antigravity-provenance-" + [guid]::NewGuid().ToString("N"))
$manual = Join-Path $tmp "manual"
$valid = Join-Path $tmp "valid"
New-Item -ItemType Directory -Force -Path $manual, $valid | Out-Null

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $manual "harness-state") | Out-Null
    Set-Content -LiteralPath (Join-Path $manual "harness-state\.gemini-private") -Value "" -Encoding ASCII
    Write-JsonFile (Join-Path $manual "harness-state\attempt-ledgers\manual.json") ([ordered]@{schema="antigravity-harness-attempt-ledger-v1";attempts=@()})
    Write-JsonFile (Join-Path $manual "harness-state\reports\manual.json") ([ordered]@{schema="antigravity-harness-completion-report-v1"})
    $manualResult = & $audit -ProjectRoot $ProjectRoot -TaskRoot $manual -NoThrow | ConvertFrom-Json
    if ($manualResult.status -ne "failed") { throw "Manual governance artifacts were accepted." }
    foreach ($code in @("decision-reference-required")) {
        if ($code -notin @($manualResult.failures)) { throw "Manual fixture missing expected failure: $code" }
    }

    $scripts = @{
        contract = "src/scripts/new-task-contract.ps1"
        ledger = "src/scripts/new-attempt-record.ps1"
        update = "src/scripts/update-attempt-record.ps1"
        report = "src/scripts/render-completion-report.ps1"
        envelope = "src/scripts/invoke-verification-envelope.ps1"
        decision = "src/scripts/invoke-completion-gate.ps1"
        taskroot = "src/scripts/new-governed-task.ps1"
        claim = "src/scripts/new-completion-claim.ps1"
    }
    $hash = @{}; foreach ($key in $scripts.Keys) { $hash[$key] = (Get-FileHash -LiteralPath (Join-Path $ProjectRoot $scripts[$key]) -Algorithm SHA256).Hash.ToLowerInvariant() }
    New-Item -ItemType Directory -Force -Path (Join-Path $valid "harness-state") | Out-Null
    Set-Content -LiteralPath (Join-Path $valid "harness-state\.gemini-private") -Value "" -Encoding ASCII
    Write-JsonFile (Join-Path $valid "harness-state\task-root.json") ([ordered]@{schema="antigravity-governed-task-root-v1";producer_script_sha256=$hash.taskroot;logical_task_id="task";task_intent_sha256=("b"*64);generation=1;task_root_sha256=("a"*64)})
    Write-JsonFile (Join-Path $valid "harness-state\contracts\task.json") ([ordered]@{schema="antigravity-harness-task-contract-v2";producer_script_sha256=$hash.contract})
    Write-JsonFile (Join-Path $valid "harness-state\attempt-ledgers\task.json") ([ordered]@{schema="antigravity-harness-attempt-ledger-v1";producer_script_sha256=$hash.ledger;last_update_script_sha256=$hash.update;attempts=@()})
    Write-JsonFile (Join-Path $valid "harness-state\reports\task.json") ([ordered]@{schema="antigravity-harness-completion-report-v1";producer_script_sha256=$hash.report})
    Write-JsonFile (Join-Path $valid "artifacts\claims\claim.json") ([ordered]@{schema="antigravity-completion-claim-v1";producer_script_sha256=$hash.claim})
    Write-JsonFile (Join-Path $valid "artifacts\verification-envelopes\run\envelope.json") ([ordered]@{schema="antigravity-verification-envelope-v2";status="passed";script_sha256=$hash.envelope})
    Write-JsonFile (Join-Path $valid "artifacts\completion-gates\run\decision.json") ([ordered]@{schema="antigravity-completion-decision-v1";status="checking";script_sha256=$hash.decision})
    Write-JsonFile (Join-Path $valid "artifacts\test-results\result.json") ([ordered]@{schema="antigravity-test-result-v1";cases=@([ordered]@{id="case";status="passed"})})
    $validResult = & $audit -ProjectRoot $ProjectRoot -TaskRoot $valid -NoThrow | ConvertFrom-Json
    if ($validResult.status -ne "failed" -or 'decision-reference-required' -notin $validResult.failures) { throw "Producer-only files must not count as an explicit evidence chain." }

    $missingIntent = Join-Path $tmp "missing-intent"
    Copy-Item -LiteralPath $valid -Destination $missingIntent -Recurse
    $missingIntentManifestPath = Join-Path $missingIntent "harness-state\task-root.json"
    $missingIntentManifest = Get-Content -LiteralPath $missingIntentManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $missingIntentManifest.PSObject.Properties.Remove("task_intent_sha256")
    Write-JsonFile $missingIntentManifestPath $missingIntentManifest
    $missingIntentResult = & $audit -ProjectRoot $ProjectRoot -TaskRoot $missingIntent -NoThrow | ConvertFrom-Json
    if ($missingIntentResult.status -ne "failed" -or "decision-reference-required" -notin @($missingIntentResult.failures)) { throw "TaskRoot without explicit decision was accepted." }

    [ordered]@{status="success";summary="Producer-only files are rejected; genuine canonical-chain acceptance is exercised in test-v4-completion.ps1.";cases=@("manual-rejected","producer-only-chain-rejected","explicit-decision-required")}|ConvertTo-Json -Compress
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
