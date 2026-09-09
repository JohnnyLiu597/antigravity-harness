param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path }
$init = Join-Path $ProjectRoot "src\scripts\init-project-harness.ps1"
$tmp = Join-Path $env:TEMP ("antigravity-scaffold-v2-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Set-Content -LiteralPath (Join-Path $tmp ".gitignore") -Value "existing-entry/" -Encoding UTF8
    & $init -Root $tmp -ProjectName "V2Fixture" | Out-Null
    if(-not(Test-Path -LiteralPath (Join-Path $tmp '.agents/rules/antigravity-harness.md'))){throw 'Modern rule discovery pointer missing.'}
    $ignore = Get-Content -LiteralPath (Join-Path $tmp ".gitignore") -Raw
    foreach ($entry in @("existing-entry/", ".gemini-trash/", "artifacts/")) {
        if ($ignore -notmatch [regex]::Escape($entry)) { throw "Scaffold .gitignore missing: $entry" }
    }
    $rules = Get-Content -LiteralPath (Join-Path $tmp ".agent\rules.md") -Raw
    foreach ($term in @("task contract", "completion gate", "harness-state", "policy-only")) {
        if ($rules -notmatch [regex]::Escape($term)) { throw "Scaffold rules missing v2 contract term: $term" }
    }
    & $init -Root $tmp -ProjectName "V2Fixture" | Out-Null
    $ignoreAgain = Get-Content -LiteralPath (Join-Path $tmp ".gitignore") -Raw
    foreach ($entry in @(".gemini-trash/", "artifacts/")) {
        if (([regex]::Matches($ignoreAgain, [regex]::Escape($entry))).Count -ne 1) {
            throw "Scaffold .gitignore is not idempotent for: $entry"
        }
    }
    $install=Join-Path $env:TEMP ('antigravity-init-layout-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $install 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath $init -Destination (Join-Path $install 'scripts/init-project-harness.ps1')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src/templates') -Destination $install -Recurse
    $target=Join-Path $install 'fixture';New-Item -ItemType Directory -Path $target | Out-Null
    & (Join-Path $install 'scripts/init-project-harness.ps1') -Root $target -ProjectName InstalledFixture | Out-Null
    if(-not(Test-Path -LiteralPath (Join-Path $target '.agent/rules.md'))){throw 'Installed template resolution failed.'}
    [ordered]@{ status = "success"; summary = "Scaffold preserves rules, adds a thin modern pointer, and works from installed layout." } | ConvertTo-Json -Compress
} finally {
    Write-Verbose "Retained scaffold fixtures: $tmp"
}
