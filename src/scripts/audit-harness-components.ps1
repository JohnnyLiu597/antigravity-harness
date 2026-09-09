param(
    [string]$ProjectRoot = ".",
    [switch]$NoThrow
)

$ErrorActionPreference = "Stop"
$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$manifestPath = Join-Path $root "src\harness.components.json"
$failures = New-Object System.Collections.Generic.List[string]
$records = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $failures.Add("missing component manifest: src/harness.components.json") | Out-Null
} else {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $maxExperimentalDays = if ($manifest.review_policy.max_experimental_ttl_days) {
            [int]$manifest.review_policy.max_experimental_ttl_days
        } else {
            90
        }
        $allowedStates = @("proposed", "experimental", "active", "deprecated", "retired")
        foreach ($component in @($manifest.components)) {
            $name = [string]$component.name
            if ([string]::IsNullOrWhiteSpace($name)) {
                $failures.Add("component is missing name") | Out-Null
                continue
            }
            if ([string]$component.status -notin $allowedStates) {
                $failures.Add("component '$name' has invalid status '$($component.status)'") | Out-Null
            }
            $ageDays = $null
            try {
                $since = [datetime]$component.status_since
                $ageDays = [int]((Get-Date).ToUniversalTime() - $since.ToUniversalTime()).TotalDays
                if ($component.status -eq "experimental" -and $ageDays -gt $maxExperimentalDays) {
                    $failures.Add("component '$name' exceeded experimental TTL ($ageDays > $maxExperimentalDays days)") | Out-Null
                }
            } catch {
                $failures.Add("component '$name' has invalid status_since") | Out-Null
            }
            foreach ($relativePath in @($component.paths)) {
                if ([string]::IsNullOrWhiteSpace([string]$relativePath)) { continue }
                if (-not (Test-Path -LiteralPath (Join-Path $root ([string]$relativePath)))) {
                    $failures.Add("component '$name' references missing path '$relativePath'") | Out-Null
                }
            }
            $records.Add([pscustomobject]@{
                name = $name
                status = [string]$component.status
                age_days = $ageDays
                paths = @($component.paths)
            }) | Out-Null
        }
    } catch {
        $failures.Add("component manifest parse failed: $($_.Exception.Message)") | Out-Null
    }
}

$result = [ordered]@{
    schema = "antigravity-harness-component-audit-v2"
    status = if ($failures.Count -eq 0) { "passed" } else { "failed" }
    project_root = $root
    failures = $failures.ToArray()
    components = $records.ToArray()
}

$json = $result | ConvertTo-Json -Depth 8 -Compress
if ($failures.Count -gt 0 -and -not $NoThrow) {
    $json | Out-Host
    throw "Harness component audit failed."
}
$json
