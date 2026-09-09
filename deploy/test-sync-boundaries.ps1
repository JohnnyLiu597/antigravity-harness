param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$syncToRuntime = Join-Path $ProjectRoot "deploy\sync-to-runtime.ps1"
$syncFromRuntime = Join-Path $ProjectRoot "deploy\sync-from-runtime.ps1"
$tmpRoot = Join-Path $env:TEMP ("gemini-sync-boundary-test-" + [guid]::NewGuid().ToString("N"))

function Write-Fixture {
    param([string]$Path, [string]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Assert-Present {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Expected path missing: $Path" }
}

function Assert-Absent {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { throw "Excluded path crossed sync boundary: $Path" }
}

function Assert-Content {
    param([string]$Path, [string]$Expected)
    Assert-Present -Path $Path
    $actual = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ($actual -ne $Expected) { throw "Unexpected content at ${Path}: $actual" }
}

New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
try {
    # Case 1: Source-to-Runtime
    $sourceProject = Join-Path $tmpRoot "source-project"
    $runtimeTarget = Join-Path $tmpRoot "runtime-target"
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceProject "src"), $runtimeTarget | Out-Null

    # Allowed
    Write-Fixture -Path (Join-Path $sourceProject "src\AGENTS.md") -Value "agents"
    Write-Fixture -Path (Join-Path $sourceProject "src\GEMINI.md") -Value "gemini"
    Write-Fixture -Path (Join-Path $sourceProject "src\skills\public-skill\SKILL.md") -Value "---`nname: public-skill`n---`n"
    Write-Fixture -Path (Join-Path $sourceProject "src\schemas\task-contract.schema.json") -Value "{}"
    Write-Fixture -Path (Join-Path $sourceProject "src\harness-evals\test-control-plane.ps1") -Value "'test'"

    # Forbidden
    Write-Fixture -Path (Join-Path $sourceProject "src\AGENTS.md.bak-20260101") -Value "backup"
    Write-Fixture -Path (Join-Path $sourceProject "src\brain\data.json") -Value "data"
    Write-Fixture -Path (Join-Path $sourceProject "src\config.json") -Value "config"
    Write-Fixture -Path (Join-Path $sourceProject "src\test.pb") -Value "pb"
    Write-Fixture -Path (Join-Path $sourceProject "src\conversations\log.jsonl") -Value "log"
    Write-Fixture -Path (Join-Path $sourceProject "src\harness-state\jobs\private.json") -Value "private state"
    Write-Fixture -Path (Join-Path $sourceProject "src\scripts\harness-state\jobs\private.json") -Value "nested private state"
    Write-Fixture -Path (Join-Path $sourceProject "src\harness-evals\runs\result.json") -Value "generated eval"

    # Runtime state
    Write-Fixture -Path (Join-Path $runtimeTarget "skills\private-skill\SKILL.md") -Value "runtime private"
    Write-Fixture -Path (Join-Path $runtimeTarget "skills\private-skill\.gemini-private") -Value "runtime-only"

    & $syncToRuntime -ProjectRoot $sourceProject -GeminiHome $runtimeTarget | Out-Null

    Assert-Present -Path (Join-Path $runtimeTarget "AGENTS.md")
    Assert-Present -Path (Join-Path $runtimeTarget "GEMINI.md")
    Assert-Present -Path (Join-Path $runtimeTarget "skills\public-skill\SKILL.md")
    Assert-Present -Path (Join-Path $runtimeTarget "schemas\task-contract.schema.json")
    Assert-Present -Path (Join-Path $runtimeTarget "harness-evals\test-control-plane.ps1")

    Assert-Absent -Path (Join-Path $runtimeTarget "AGENTS.md.bak-20260101")
    Assert-Absent -Path (Join-Path $runtimeTarget "brain\data.json")
    Assert-Absent -Path (Join-Path $runtimeTarget "config.json")
    Assert-Absent -Path (Join-Path $runtimeTarget "test.pb")
    Assert-Absent -Path (Join-Path $runtimeTarget "conversations\log.jsonl")
    Assert-Absent -Path (Join-Path $runtimeTarget "harness-state\jobs\private.json")
    Assert-Absent -Path (Join-Path $runtimeTarget "scripts\harness-state\jobs\private.json")
    Assert-Absent -Path (Join-Path $runtimeTarget "harness-evals\runs\result.json")

    Assert-Content -Path (Join-Path $runtimeTarget "skills\private-skill\SKILL.md") -Expected "runtime private"
    Assert-Present -Path (Join-Path $runtimeTarget "skills\private-skill\.gemini-private")

    # Case 2: Runtime-to-Source
    $runtimeSource = Join-Path $tmpRoot "runtime-source"
    $importProject = Join-Path $tmpRoot "import-project"
    New-Item -ItemType Directory -Force -Path $runtimeSource, $importProject | Out-Null

    Write-Fixture -Path (Join-Path $runtimeSource "AGENTS.md") -Value "runtime agents"
    Write-Fixture -Path (Join-Path $runtimeSource "GEMINI.md") -Value "runtime gemini"
    Write-Fixture -Path (Join-Path $runtimeSource "skills\public-skill\SKILL.md") -Value "---`nname: public-skill`n---`n"
    Write-Fixture -Path (Join-Path $runtimeSource "schemas\task-contract.schema.json") -Value "{}"
    Write-Fixture -Path (Join-Path $runtimeSource "harness-evals\test-control-plane.ps1") -Value "'test'"

    Write-Fixture -Path (Join-Path $runtimeSource "config.json") -Value "config"
    Write-Fixture -Path (Join-Path $runtimeSource "brain\data.json") -Value "data"
    Write-Fixture -Path (Join-Path $runtimeSource "AGENTS.md.bak-20260101") -Value "backup"
    Write-Fixture -Path (Join-Path $runtimeSource "test.pb") -Value "pb"
    Write-Fixture -Path (Join-Path $runtimeSource "conversations\log.jsonl") -Value "log"
    Write-Fixture -Path (Join-Path $runtimeSource "harness-state\jobs\private.json") -Value "private state"
    Write-Fixture -Path (Join-Path $runtimeSource "scripts\harness-state\jobs\private.json") -Value "nested private state"
    Write-Fixture -Path (Join-Path $runtimeSource "harness-evals\runs\result.json") -Value "generated eval"

    Write-Fixture -Path (Join-Path $runtimeSource "skills\private-skill\SKILL.md") -Value "runtime private"
    Write-Fixture -Path (Join-Path $runtimeSource "skills\private-skill\.gemini-private") -Value "runtime-only"
    Write-Fixture -Path (Join-Path $runtimeSource "skills\builtin-skill\.gemini-private") -Value "runtime-only"

    & $syncFromRuntime -ProjectRoot $importProject -GeminiHome $runtimeSource -Refresh | Out-Null

    Assert-Present -Path (Join-Path $importProject "src\AGENTS.md")
    Assert-Present -Path (Join-Path $importProject "src\GEMINI.md")
    Assert-Present -Path (Join-Path $importProject "src\skills\public-skill\SKILL.md")
    Assert-Present -Path (Join-Path $importProject "src\schemas\task-contract.schema.json")
    Assert-Present -Path (Join-Path $importProject "src\harness-evals\test-control-plane.ps1")

    Assert-Absent -Path (Join-Path $importProject "src\config.json")
    Assert-Absent -Path (Join-Path $importProject "src\brain\data.json")
    Assert-Absent -Path (Join-Path $importProject "src\AGENTS.md.bak-20260101")
    Assert-Absent -Path (Join-Path $importProject "src\test.pb")
    Assert-Absent -Path (Join-Path $importProject "src\conversations\log.jsonl")
    Assert-Absent -Path (Join-Path $importProject "src\harness-state\jobs\private.json")
    Assert-Absent -Path (Join-Path $importProject "src\scripts\harness-state\jobs\private.json")
    Assert-Absent -Path (Join-Path $importProject "src\harness-evals\runs\result.json")
    Assert-Absent -Path (Join-Path $importProject "src\skills\private-skill")
    Assert-Absent -Path (Join-Path $importProject "src\skills\builtin-skill")

    [ordered]@{
        status = "success"
        summary = "Runtime/source sync boundaries correctly tested."
        cases = @("source-to-runtime", "runtime-to-source")
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    # Retain successful and failed fixtures for inspection; user controls cleanup.
    Write-Verbose "Retained sync boundary fixtures: $tmpRoot"
}
