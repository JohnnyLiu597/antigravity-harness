param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$verifyManifest = Join-Path $ProjectRoot "src\scripts\verify-manifest-integrity.ps1"
$probeSurfaces = Join-Path $ProjectRoot "src\scripts\probe-native-surfaces.ps1"
$auditComponents = Join-Path $ProjectRoot "src\scripts\audit-harness-components.ps1"

foreach ($required in @($verifyManifest, $probeSurfaces, $auditComponents)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Truth-reset implementation is missing: $required"
    }
}

$repoResult = & $verifyManifest -ProjectRoot $ProjectRoot -NoThrow | ConvertFrom-Json
if ($repoResult.status -ne "passed") {
    throw "Repository manifests are not truthful: $($repoResult.failures -join '; ')"
}

$tmpRoot = Join-Path $env:TEMP ("antigravity-truth-reset-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $tmpRoot "src\scripts") | Out-Null

try {
    $phantomCapabilities = [ordered]@{
        schema = "antigravity-harness-capabilities-v2"
        capabilities = @(
            [ordered]@{
                id = "phantom"
                implementation_status = "implemented"
                availability = "available"
                enforcement_mode = "script-enforced"
                verification = [ordered]@{ script = "src/scripts/missing.ps1"; evidence = @() }
            },
            [ordered]@{
                id = "fake-verified"
                implementation_status = "verified"
                availability = "available"
                enforcement_mode = "script-enforced"
                verification = [ordered]@{ script = "src/scripts/existing.ps1"; evidence = @("artifacts/missing-evidence.json") }
            }
        )
    }
    $phantomComponents = [ordered]@{
        schema = "antigravity-harness-components-v2"
        review_policy = [ordered]@{ max_experimental_ttl_days = 90 }
        components = @()
    }
    $phantomCapabilities | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tmpRoot "src\harness.capabilities.json") -Encoding UTF8
    $phantomComponents | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tmpRoot "src\harness.components.json") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmpRoot "src\scripts\existing.ps1") -Value "'ok'" -Encoding UTF8

    $phantomResult = & $verifyManifest -ProjectRoot $tmpRoot -NoThrow | ConvertFrom-Json
    if ($phantomResult.status -ne "failed" -or
        -not (@($phantomResult.failures) -match "missing verification script")) {
        throw "Manifest integrity did not reject a phantom implemented capability."
    }
    if (-not (@($phantomResult.failures) -match "missing verification evidence")) {
        throw "Manifest integrity did not reject a verified capability with missing evidence."
    }

    $expiredComponents = [ordered]@{
        schema = "antigravity-harness-components-v2"
        review_policy = [ordered]@{ max_experimental_ttl_days = 90 }
        components = @(
            [ordered]@{
                name = "expired-component"
                type = "script"
                status = "experimental"
                status_since = "2025-01-01"
                paths = @("src/scripts")
            }
        )
    }
    $expiredComponents | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tmpRoot "src\harness.components.json") -Encoding UTF8
    $componentResult = & $auditComponents -ProjectRoot $tmpRoot -NoThrow | ConvertFrom-Json
    if ($componentResult.status -ne "failed" -or
        -not (@($componentResult.failures) -match "experimental TTL")) {
        throw "Component audit did not reject expired experimental metadata."
    }

    $surfaceRaw = & $probeSurfaces -ProjectRoot $ProjectRoot
    $surfaceResult = $surfaceRaw | ConvertFrom-Json
    if ($surfaceResult.PSObject.Properties.Name -contains "project_root" -or
        $surfaceResult.PSObject.Properties.Name -contains "runtime_root") {
        throw "Native surface probe exposed absolute roots instead of safe hashes/labels."
    }
    foreach ($surfaceName in @("ask_question", "planning_mode", "manage_task", "schedule", "invoke_subagent")) {
        $surface = @($surfaceResult.surfaces | Where-Object { $_.name -eq $surfaceName })
        if ($surface.Count -ne 1) {
            throw "Native surface probe omitted $surfaceName."
        }
        if ($surface[0].availability -eq "available" -and -not $surface[0].evidence) {
            throw "Native surface probe claimed $surfaceName available without evidence."
        }
    }

    [ordered]@{
        status = "success"
        summary = "Truth registry rejects phantom capabilities and stale components while native-only surfaces remain evidence-bound."
        cases = @("repository-integrity", "phantom-capability", "component-ttl", "native-surface-evidence")
    } | ConvertTo-Json -Depth 6 -Compress
} finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}
