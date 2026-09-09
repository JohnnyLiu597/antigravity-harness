param(
    [Parameter(Mandatory = $true)][string]$LedgerPath
)

$ErrorActionPreference = "Stop"
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function New-Error([string]$Code, [string]$Summary) {
    [ordered]@{ status = "error"; error_code = $Code; summary = $Summary } | ConvertTo-Json -Compress
}

try {
    $path = (Resolve-Path -LiteralPath $LedgerPath).Path
    $stateRoot = Split-Path -Parent (Split-Path -Parent $path)
    if (-not (Test-Path -LiteralPath (Join-Path $stateRoot ".gemini-private") -PathType Leaf)) {
        Write-Output (New-Error "state_root_not_private" "Attempt ledger is not under a marked private state root.")
        return
    }
    $ledger = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $attempts = @($ledger.attempts | Sort-Object sequence)
    if ($attempts.Count -eq 0 -or @($attempts | Where-Object { $_.status -eq "running" }).Count -gt 0) {
        Write-Output (New-Error "attempts_incomplete" "Every attempt must be terminal before rendering completion truth.")
        return
    }
    $failed = @($attempts | Where-Object { $_.status -in @("failed", "rejected", "blocked") })
    $last = $attempts[-1]
    $reportStatus = if ($last.status -eq "passed" -and $failed.Count -gt 0) { "passed_after_retry" } elseif ($last.status -eq "passed") { "passed" } else { [string]$last.status }
    $safeAttempts = @($attempts | ForEach-Object {
        [ordered]@{
            attempt_id = $_.attempt_id
            sequence = $_.sequence
            operation_id = $_.operation_id
            input_sha256 = $_.input_sha256
            workspace_before_sha256 = $_.workspace_before_sha256
            workspace_after_sha256 = $_.workspace_after_sha256
            changed_paths = @($_.changed_paths)
            status = $_.status
            started_at = $_.started_at
            completed_at = $_.completed_at
            exit_code = $_.exit_code
            failure_class = $_.failure_class
            side_effects_observed = $_.side_effects_observed
            recovery_action = $_.recovery_action
            evidence_artifact = $_.evidence_artifact
            evidence_sha256 = $_.evidence_sha256
        }
    })
    $report = [ordered]@{
        schema = "antigravity-harness-completion-report-v1"
        producer_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        task_id = $ledger.task_id
        ledger_path_sha256 = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes($path.ToLowerInvariant())))).Replace("-", "").ToLowerInvariant()
        ledger_sha256 = Get-Sha256 $path
        ledger_version = $ledger.version
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        status = $reportStatus
        attempt_count = $attempts.Count
        failed_count = $failed.Count
        passed_count = @($attempts | Where-Object { $_.status -eq "passed" }).Count
        attempts = $safeAttempts
    }
    $reportRoot = Join-Path $stateRoot "reports"
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
    $reportPath = Join-Path $reportRoot ($ledger.task_id + "-" + (Get-Date).ToString("yyyyMMdd-HHmmssfff") + ".json")
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    [ordered]@{ status = "success"; report_status = $reportStatus; report = $reportPath; report_sha256 = Get-Sha256 $reportPath; ledger_sha256 = $report.ledger_sha256 } | ConvertTo-Json -Compress
} catch {
    New-Error "completion_report_failed" "Completion report could not be rendered."
}
