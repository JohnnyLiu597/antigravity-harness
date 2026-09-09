param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$verifierPath = Join-Path $ProjectRoot "deploy\verify-package.ps1"
$content = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8
foreach ($required in @(
    "verify-manifest-integrity.ps1",
    "test-control-plane.ps1",
    "test-verification-plane.ps1",
    "test-governance-contracts.ps1",
    "completion-claim.schema.json",
    "verification-envelope.schema.json",
    "attempt-ledger.schema.json",
    "new-attempt-record.ps1",
    "update-attempt-record.ps1",
    "render-completion-report.ps1",
    "audit-governed-execution.ps1",
    "new-governed-task.ps1",
    "new-completion-claim.ps1",
    "test-attempt-ledger.ps1",
    "test-execution-provenance.ps1",
    "test-desktop-hook-probe.ps1",
    "install-desktop-hook-plugin.ps1",
    "audit-desktop-hook-session.ps1",
    "new-desktop-session-binding.ps1",
    "v3-session-task-binding.md",
    "v3-core-tool-observation.md",
    "desktop-hooks",
    "reliable-maker-control",
    "docs\completion-truth.md",
    "docs\verification-gate.md"
)) {
    if ($content -notmatch [regex]::Escape($required)) {
        throw "Package verifier is missing v2 truth surface: $required"
    }
}

[ordered]@{
    status = "success"
    summary = "Package verification requires the v2 truth, control, verification, governance, schema, and documentation surfaces."
} | ConvertTo-Json -Compress
