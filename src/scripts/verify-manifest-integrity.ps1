param(
    [string]$ProjectRoot = ".",
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$capabilitiesPath = Join-Path $root "src\harness.capabilities.json"
$componentAudit = Join-Path $PSScriptRoot "audit-harness-components.ps1"
$failures = New-Object System.Collections.Generic.List[string]
$records = New-Object System.Collections.Generic.List[object]

$allowedImplementation = @("declared", "implemented", "verified")
$allowedAvailability = @("unverified", "available", "unavailable")
$allowedEnforcement = @("native-enforced", "script-enforced", "human-enforced", "policy-only", "unverified")

if (-not (Test-Path -LiteralPath $capabilitiesPath -PathType Leaf)) {
    $failures.Add("missing capability manifest: src/harness.capabilities.json") | Out-Null
} else {
    try {
        $manifest = Get-Content -LiteralPath $capabilitiesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $capabilities = if ($manifest.capabilities) { @($manifest.capabilities) } else { @($manifest.capability_profiles) }
        foreach ($capability in $capabilities) {
            $id = [string]$capability.id
            if ([string]::IsNullOrWhiteSpace($id)) {
                $failures.Add("capability is missing id") | Out-Null
                continue
            }
            $implementation = [string]$capability.implementation_status
            $availability = [string]$capability.availability
            $enforcement = [string]$capability.enforcement_mode
            if ($implementation -notin $allowedImplementation) {
                $failures.Add("capability '$id' has invalid or missing implementation_status") | Out-Null
            }
            if ($availability -notin $allowedAvailability) {
                $failures.Add("capability '$id' has invalid or missing availability") | Out-Null
            }
            if ($enforcement -notin $allowedEnforcement) {
                $failures.Add("capability '$id' has invalid or missing enforcement_mode") | Out-Null
            }

            $verification = $capability.verification
            $scriptPath = if ($verification -and $verification.script) { [string]$verification.script } else { "" }
            $evidence = if ($verification -and $verification.evidence) { @($verification.evidence) } else { @() }
            if ($scriptPath -and -not (Test-Path -LiteralPath (Join-Path $root $scriptPath))) {
                $failures.Add("capability '$id' references missing verification script '$scriptPath'") | Out-Null
            }
            foreach ($evidencePath in $evidence) {
                try {
                    $candidate = [System.IO.Path]::GetFullPath((Join-Path $root ([string]$evidencePath)))
                    $rootPrefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
                    if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
                        -not (Test-Path -LiteralPath $candidate)) {
                        $failures.Add("capability '$id' references missing verification evidence '$evidencePath'") | Out-Null
                    }
                } catch {
                    $failures.Add("capability '$id' references missing verification evidence '$evidencePath'") | Out-Null
                }
            }
            if ($implementation -eq "verified") {
                if ($availability -ne "available") {
                    $failures.Add("verified capability '$id' is not available") | Out-Null
                }
                if (-not $scriptPath -or $evidence.Count -eq 0) {
                    $failures.Add("verified capability '$id' lacks verification script or evidence") | Out-Null
                }
            }
            if ($enforcement -eq "native-enforced" -and ($availability -ne "available" -or $evidence.Count -eq 0)) {
                $failures.Add("native-enforced capability '$id' lacks live availability evidence") | Out-Null
            }
            $records.Add([pscustomobject]@{
                id = $id
                implementation_status = $implementation
                availability = $availability
                enforcement_mode = $enforcement
                verification_script = $scriptPath
                evidence_count = $evidence.Count
            }) | Out-Null
        }
    } catch {
        $failures.Add("capability manifest parse failed: $($_.Exception.Message)") | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $componentAudit -PathType Leaf)) {
    $failures.Add("missing component audit implementation") | Out-Null
} else {
    try {
        $componentResult = & $componentAudit -ProjectRoot $root -NoThrow | ConvertFrom-Json
        foreach ($failure in @($componentResult.failures)) {
            $failures.Add([string]$failure) | Out-Null
        }
    } catch {
        $failures.Add("component audit invocation failed: $($_.Exception.Message)") | Out-Null
    }
}

$result = [ordered]@{
    schema = "antigravity-harness-manifest-integrity-v2"
    status = if ($failures.Count -eq 0) { "passed" } else { "failed" }
    project_root = $root
    failures = $failures.ToArray()
    capabilities = $records.ToArray()
}

$json = $result | ConvertTo-Json -Depth 8 -Compress
if ($failures.Count -gt 0 -and -not $NoThrow) {
    $json | Out-Host
    throw "Harness manifest integrity failed."
}
$json
