param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$JobPath,
    [Parameter(Mandatory = $true)]
    [ValidateSet("drafted", "approved", "running", "checking", "waiting_approval", "verified", "blocked", "stopped")]
    [string]$ToState,
    [ValidateRange(-1, 2147483647)]
    [int]$ExpectedVersion = -1,
    [string]$ProgressSummary = "",
    [string]$NextAction = "",
    [string[]]$Blockers = @(),
    [string]$StopReason = "",
    [string]$VerifiedCommit = "",
    [string]$WorkspaceFingerprint = "",
    [string]$VerificationArtifact = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-ErrorJson {
    param(
        [string]$Code,
        [string]$Message,
        [string]$State,
        [int]$Version
    )
    return ([ordered]@{
        status = "error"
        error_code = $Code
        error = $Message
        state = $State
        version = $Version
    } | ConvertTo-Json -Depth 4 -Compress)
}

function Write-JsonNoBom {
    param(
        [string]$Path,
        $Value
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 14), $encoding)
}

try {
    $resolvedJobPath = (Resolve-Path -LiteralPath $JobPath).Path
    $job = Get-Content -LiteralPath $resolvedJobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($job.schema -ne "antigravity-harness-job-state-v2") {
        throw "Unsupported job state schema: $($job.schema)"
    }

    $currentState = [string]$job.state
    $currentVersion = [int]$job.version
    if ($ExpectedVersion -ge 0 -and $ExpectedVersion -ne $currentVersion) {
        Write-Output (New-ErrorJson -Code "version_conflict" -Message "Expected version $ExpectedVersion but current version is $currentVersion." -State $currentState -Version $currentVersion)
        return
    }

    $terminalStates = @("verified", "blocked", "stopped")
    if ($currentState -in $terminalStates) {
        Write-Output (New-ErrorJson -Code "terminal_state" -Message "Terminal job state '$currentState' is immutable; create a new job attempt to continue." -State $currentState -Version $currentVersion)
        return
    }

    $validTransitions = @{
        drafted = @("approved", "blocked", "stopped")
        approved = @("running", "blocked", "stopped")
        running = @("checking", "waiting_approval", "blocked", "stopped")
        checking = @("verified", "waiting_approval", "blocked", "stopped")
        waiting_approval = @("stopped")
    }
    if (-not $validTransitions.ContainsKey($currentState) -or $ToState -notin $validTransitions[$currentState]) {
        Write-Output (New-ErrorJson -Code "invalid_transition" -Message "Transition '$currentState' -> '$ToState' is not allowed." -State $currentState -Version $currentVersion)
        return
    }

    if ($ToState -eq "checking" -and $WorkspaceFingerprint -notmatch '^[a-fA-F0-9]{64}$') {
        Write-Output (New-ErrorJson -Code "missing_checking_fingerprint" -Message "Entering checking requires a 64-character workspace fingerprint." -State $currentState -Version $currentVersion)
        return
    }

    if ($ToState -eq "verified") {
        if ([string]::IsNullOrWhiteSpace($VerifiedCommit) -or
            $WorkspaceFingerprint -notmatch '^[a-fA-F0-9]{64}$' -or
            [string]::IsNullOrWhiteSpace($VerificationArtifact) -or
            [string]::IsNullOrWhiteSpace($StopReason)) {
            Write-Output (New-ErrorJson -Code "verification_evidence_required" -Message "Verified state requires commit, workspace fingerprint, verification artifact, and stop reason." -State $currentState -Version $currentVersion)
            return
        }
    }

    if ($ToState -in @("blocked", "stopped") -and [string]::IsNullOrWhiteSpace($StopReason)) {
        Write-Output (New-ErrorJson -Code "stop_reason_required" -Message "State '$ToState' requires a stop reason." -State $currentState -Version $currentVersion)
        return
    }
    if ($ToState -eq "waiting_approval" -and @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        Write-Output (New-ErrorJson -Code "approval_blocker_required" -Message "waiting_approval requires at least one explicit blocker or approval request." -State $currentState -Version $currentVersion)
        return
    }

    $newVersion = $currentVersion + 1
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $job.state = $ToState
    $job.version = $newVersion
    $job.updated_at = $now
    if (-not [string]::IsNullOrWhiteSpace($ProgressSummary)) {
        $job.last_progress = $ProgressSummary.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($NextAction)) {
        $job.next_action = $NextAction.Trim()
    } elseif ($ToState -in @("verified", "blocked", "stopped")) {
        $job.next_action = $null
    }

    $newBlockers = @($Blockers | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) { $_.Trim() }
    })
    if ($newBlockers.Count -gt 0) {
        $job.blockers = @(@($job.blockers) + $newBlockers | Sort-Object -Unique)
    }
    if (-not [string]::IsNullOrWhiteSpace($StopReason)) {
        $job.stop_reason = $StopReason.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($VerifiedCommit)) {
        $job.verification.verified_commit = $VerifiedCommit.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkspaceFingerprint)) {
        $job.verification.workspace_fingerprint = $WorkspaceFingerprint.ToLowerInvariant()
    }
    if (-not [string]::IsNullOrWhiteSpace($VerificationArtifact)) {
        $job.verification.artifact = $VerificationArtifact.Trim()
    }

    $history = @($job.history)
    $history += [pscustomobject]@{
        version = $newVersion
        timestamp = $now
        from = $currentState
        to = $ToState
        summary = if ([string]::IsNullOrWhiteSpace($ProgressSummary)) { "$currentState -> $ToState" } else { $ProgressSummary.Trim() }
    }
    $job.history = $history

    $temporaryPath = $resolvedJobPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    Write-JsonNoBom -Path $temporaryPath -Value $job
    Move-Item -LiteralPath $temporaryPath -Destination $resolvedJobPath -Force

    [ordered]@{
        status = "success"
        job_id = $job.job_id
        path = $resolvedJobPath
        previous_state = $currentState
        state = $ToState
        version = $newVersion
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    [ordered]@{
        status = "error"
        error_code = "job_state_update_failed"
        error = $_.Exception.Message
        state = $null
        version = $null
    } | ConvertTo-Json -Depth 4 -Compress
}
