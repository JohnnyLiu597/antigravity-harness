param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ($ProjectRoot) { Set-Location (Resolve-Path -LiteralPath $ProjectRoot).Path }
$results = New-Object System.Collections.Generic.List[object]

function Invoke-Case {
    param([string]$Id, [scriptblock]$Action)
    try {
        & $Action
        $results.Add([pscustomobject]@{ id=$Id; status="passed" }) | Out-Null
    } catch {
        $results.Add([pscustomobject]@{ id=$Id; status="failed"; error=$_.Exception.Message }) | Out-Null
    }
}

$docPath = "docs/getting-started.md"
$script:docContent = ""

Invoke-Case "file-exists" {
    if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) { throw "getting-started.md missing" }
    $script:docContent = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8
    if ($script:docContent.Length -le 100) { throw "getting-started.md is empty" }
}

Invoke-Case "required-sections" {
    foreach ($section in @("# Getting Started with Antigravity Harness", "## Core Concepts", "## Standard Workflow", "## Tier 0 vs Tier 1 Routing", "## Evaluation Conversations")) {
        if (-not $script:docContent.Contains($section)) { throw "Missing section: $section" }
    }
}

Invoke-Case "governance-concepts" {
    foreach ($concept in @("Task Contract", "Scope Guard", "Attempt Ledger", "Verification Envelope", "Completion Gate", "passed_after_retry")) {
        if (-not $script:docContent.Contains($concept)) { throw "Missing concept: $concept" }
    }
}

Invoke-Case "line-budget" {
    $lineCount = @($script:docContent -split "\r?\n").Count
    if ($lineCount -gt 200) { throw "Line count exceeds 200: $lineCount" }
}

Invoke-Case "encoding-clean" {
    if ($script:docContent.Contains([char]0xFFFD) -or $script:docContent.Contains([char]0x9239)) { throw "Detected mojibake or replacement characters" }
}

Invoke-Case "private-state-semantics" {
    if (-not $script:docContent.Contains('$env:USERPROFILE\.gemini\harness-state')) { throw "Canonical harness-state root missing" }
    if ($script:docContent -notmatch '\.gemini-private.*marker file') { throw ".gemini-private must be described as a marker file" }
    if ($script:docContent -match 'located in private state.*gemini-private') { throw ".gemini-private is incorrectly described as a state directory" }
}

Invoke-Case "referenced-scripts-exist" {
    foreach ($path in @("src/scripts/new-task-contract.ps1", "src/scripts/test-task-scope.ps1", "src/scripts/new-attempt-record.ps1", "src/scripts/update-attempt-record.ps1", "src/scripts/invoke-verification-envelope.ps1", "src/scripts/render-completion-report.ps1", "src/scripts/invoke-completion-gate.ps1", "src/skills/reliable-maker-control/SKILL.md")) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Referenced path missing: $path" }
    }
    foreach ($term in @("-ObserveWorkspace", "-TestResultPath", "-RequireStructuredTestResult", "-AcceptanceCriteria")) {
        if ($script:docContent -notmatch [regex]::Escape($term)) { throw "Required example argument missing: $term" }
    }
}

$report = [ordered]@{
    schema = "antigravity-test-result-v1"
    cases = $results.ToArray()
}
New-Item -ItemType Directory -Force -Path "artifacts/test-results" | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "artifacts/test-results/getting-started.json" -Encoding UTF8

$failed = @($results | Where-Object { $_.status -eq "failed" })
Write-Output "tests_collected=$($results.Count)"
Write-Output "$($results.Count - $failed.Count) passed"
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Error "$($_.id): $($_.error)" }
    exit 1
}
exit 0
