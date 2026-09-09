param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [string]$WorkingDirectory = ".",
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 60,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')]
    [string]$OperationId,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IdempotencyKey,
    [string]$StateRoot = "",
    [ValidateRange(1, 30)]
    [int]$LockTimeoutSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DefaultStateRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:GEMINI_HARNESS_STATE_ROOT)) {
        return $env:GEMINI_HARNESS_STATE_ROOT
    }
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw "StateRoot is required when USERPROFILE is unavailable."
    }
    return (Join-Path $env:USERPROFILE ".gemini\harness-state")
}

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-QuotedProcessArgument {
    param([AllowEmptyString()][string]$Argument)
    if ($null -eq $Argument) { $Argument = "" }
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ([int]$character -eq 92) {
            $backslashCount++
            continue
        }
        if ([int]$character -eq 34) {
            if ($backslashCount -gt 0) {
                [void]$builder.Append(('\' * ($backslashCount * 2)))
            }
            [void]$builder.Append('\"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Write-JsonNoBom {
    param(
        [string]$Path,
        $Value
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), $encoding)
}

function Write-AtomicJson {
    param(
        [string]$Path,
        $Value
    )
    $parent = Split-Path -Parent $Path
    $temporaryPath = Join-Path $parent (".tmp-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    Write-JsonNoBom -Path $temporaryPath -Value $Value
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function New-BlockedResult {
    param(
        [string]$Code,
        [string]$Summary,
        [string]$CommandFingerprint,
        [string]$IdempotencyHash
    )
    return [ordered]@{
        schema = "antigravity-harness-safe-command-result-v2"
        status = "blocked"
        executed = $false
        duplicate_prevented = $true
        timed_out = $false
        exit_code = $null
        operation_id = $OperationId
        command_fingerprint = $CommandFingerprint
        idempotency_key_sha256 = $IdempotencyHash
        error_code = $Code
        error_summary = $Summary
        event_path = $null
    }
}

$lockStream = $null
$process = $null
$stage = "initialization"
try {
    $stage = "state-root-policy"
    if ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $StateRoot = Get-DefaultStateRoot
    }
    $resolvedStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
    $defaultStateRoot = [System.IO.Path]::GetFullPath((Get-DefaultStateRoot)).TrimEnd('\', '/')
    $isDefaultStateRoot = $resolvedStateRoot.TrimEnd('\', '/').Equals($defaultStateRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedStateRoot.StartsWith($defaultStateRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $isDefaultStateRoot -and -not (Test-Path -LiteralPath (Join-Path $resolvedStateRoot ".gemini-private") -PathType Leaf)) {
        throw "A custom StateRoot must already contain a .gemini-private marker created by the task-contract workflow."
    }
    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    if (-not (Test-Path -LiteralPath $resolvedWorkingDirectory -PathType Container)) {
        throw "Working directory is not a directory."
    }

    $stage = "command-resolution"
    $commandInfo = Get-Command $FilePath -ErrorAction Stop | Select-Object -First 1
    $resolvedExecutable = if (-not [string]::IsNullOrWhiteSpace($commandInfo.Source)) {
        $commandInfo.Source
    } elseif (-not [string]::IsNullOrWhiteSpace($commandInfo.Path)) {
        $commandInfo.Path
    } else {
        $FilePath
    }

    $canonicalDescriptor = $resolvedExecutable.ToLowerInvariant() + "`n" +
        $resolvedWorkingDirectory.ToLowerInvariant() + "`n" +
        (@($ArgumentList) -join "`0")
    $commandFingerprint = Get-Sha256Text -Value $canonicalDescriptor
    $idempotencyHash = Get-Sha256Text -Value $IdempotencyKey
    $workingDirectoryHash = Get-Sha256Text -Value $resolvedWorkingDirectory.ToLowerInvariant()

    $stage = "state-directory"
    New-Item -ItemType Directory -Force -Path $resolvedStateRoot | Out-Null
    $privateMarker = Join-Path $resolvedStateRoot ".gemini-private"
    if (-not (Test-Path -LiteralPath $privateMarker -PathType Leaf)) {
        [System.IO.File]::WriteAllText($privateMarker, "", (New-Object System.Text.UTF8Encoding($false)))
    }
    $eventsRoot = Join-Path $resolvedStateRoot "tool-events"
    $idempotencyRoot = Join-Path $resolvedStateRoot "idempotency"
    New-Item -ItemType Directory -Force -Path $eventsRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $idempotencyRoot | Out-Null

    $stage = "idempotency-lock"
    $indexPath = Join-Path $idempotencyRoot ($idempotencyHash + ".json")
    $lockPath = Join-Path $idempotencyRoot ($idempotencyHash + ".lock")
    $lockDeadline = (Get-Date).AddSeconds($LockTimeoutSeconds)
    while ($null -eq $lockStream -and (Get-Date) -lt $lockDeadline) {
        try {
            $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            [System.Threading.Thread]::Sleep(100)
        }
    }
    if ($null -eq $lockStream) {
        (New-BlockedResult -Code "operation_locked" -Summary "Another attempt currently owns this idempotency key." -CommandFingerprint $commandFingerprint -IdempotencyHash $idempotencyHash) | ConvertTo-Json -Depth 5 -Compress
        return
    }

    $stage = "idempotency-reconcile"
    $priorIndex = $null
    if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
        $priorIndex = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($priorIndex.command_fingerprint -ne $commandFingerprint -or $priorIndex.operation_id -ne $OperationId) {
            (New-BlockedResult -Code "idempotency_conflict" -Summary "The idempotency key is already bound to a different logical command." -CommandFingerprint $commandFingerprint -IdempotencyHash $idempotencyHash) | ConvertTo-Json -Depth 5 -Compress
            return
        }
        if ($priorIndex.last_status -eq "succeeded") {
            $priorEvent = $null
            if (-not [string]::IsNullOrWhiteSpace($priorIndex.last_event_path) -and (Test-Path -LiteralPath $priorIndex.last_event_path -PathType Leaf)) {
                $priorEvent = Get-Content -LiteralPath $priorIndex.last_event_path -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            if ($null -eq $priorEvent) {
                (New-BlockedResult -Code "previous_evidence_missing" -Summary "The prior success cannot be reconciled because its event evidence is missing." -CommandFingerprint $commandFingerprint -IdempotencyHash $idempotencyHash) | ConvertTo-Json -Depth 5 -Compress
                return
            }
            [ordered]@{
                schema = "antigravity-harness-safe-command-result-v2"
                status = "already_satisfied"
                executed = $false
                duplicate_prevented = $true
                timed_out = $false
                exit_code = $priorEvent.exit_code
                operation_id = $OperationId
                attempt_number = [int]$priorIndex.attempt_count
                command_fingerprint = $commandFingerprint
                idempotency_key_sha256 = $idempotencyHash
                stdout_sha256 = $priorEvent.stdout_sha256
                stderr_sha256 = $priorEvent.stderr_sha256
                stdout_bytes = $priorEvent.stdout_bytes
                stderr_bytes = $priorEvent.stderr_bytes
                error_code = $null
                error_summary = $null
                event_path = $priorIndex.last_event_path
            } | ConvertTo-Json -Depth 6 -Compress
            return
        }
        if ($priorIndex.last_status -ne "succeeded") {
            (New-BlockedResult -Code "previous_attempt_uncertain" -Summary "The previous attempt may have produced side effects; reconcile external state before retrying." -CommandFingerprint $commandFingerprint -IdempotencyHash $idempotencyHash) | ConvertTo-Json -Depth 5 -Compress
            return
        }
    }

    $attemptNumber = if ($null -eq $priorIndex) { 1 } else { [int]$priorIndex.attempt_count + 1 }
    $attemptId = [guid]::NewGuid().ToString("N")
    $eventId = [guid]::NewGuid().ToString("N")
    $eventPath = Join-Path $eventsRoot ($eventId + ".json")
    $runningIndex = [ordered]@{
        schema = "antigravity-harness-idempotency-index-v2"
        operation_id = $OperationId
        idempotency_key_sha256 = $idempotencyHash
        command_fingerprint = $commandFingerprint
        attempt_count = $attemptNumber
        last_status = "running"
        last_attempt_id = $attemptId
        last_event_path = $null
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $stage = "running-evidence"
    Write-AtomicJson -Path $indexPath -Value $runningIndex

    $startedAt = Get-Date
    $stdoutText = ""
    $stderrText = ""
    $timedOut = $false
    $exitCode = $null
    $executed = $false
    $eventStatus = "start_failed"
    $errorCode = "process_start_failed"
    $errorSummary = "The process could not be started."

    $stage = "process-execution"
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $resolvedExecutable
        $startInfo.WorkingDirectory = $resolvedWorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-QuotedProcessArgument -Argument $_ }) -join " ")

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $executed = $process.Start()
        if (-not $executed) {
            throw "Process start returned false."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            $timedOut = $true
            try {
                $taskKill = Join-Path $env:SystemRoot "System32\taskkill.exe"
                if (Test-Path -LiteralPath $taskKill -PathType Leaf) {
                    & $taskKill /PID $process.Id /T /F 2>$null | Out-Null
                } else {
                    $process.Kill()
                }
            } catch {
                try { $process.Kill() } catch { }
            }
            [void]$process.WaitForExit(5000)
        } else {
            $process.WaitForExit()
        }

        try { $stdoutText = $stdoutTask.GetAwaiter().GetResult() } catch { $stdoutText = "" }
        try { $stderrText = $stderrTask.GetAwaiter().GetResult() } catch { $stderrText = "" }
        if ($process.HasExited) {
            $exitCode = [int]$process.ExitCode
        }

        if ($timedOut) {
            $eventStatus = "timed_out"
            $errorCode = "command_timeout"
            $errorSummary = "The command exceeded its bounded timeout and was stopped. Side effects require reconciliation before retry."
        } elseif ($exitCode -eq 0) {
            $eventStatus = "succeeded"
            $errorCode = $null
            $errorSummary = $null
        } else {
            $eventStatus = "failed"
            $errorCode = "process_exit_nonzero"
            $errorSummary = "The process exited with a non-zero code."
        }
    } catch {
        $eventStatus = "start_failed"
        $errorCode = "process_start_failed"
        $errorSummary = "The process could not be started."
    }

    $durationMs = [int]((Get-Date) - $startedAt).TotalMilliseconds
    $stdoutHash = Get-Sha256Text -Value $stdoutText
    $stderrHash = Get-Sha256Text -Value $stderrText
    $event = [ordered]@{
        schema = "antigravity-harness-tool-event-v2"
        event_id = $eventId
        operation_id = $OperationId
        attempt_id = $attemptId
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        status = $eventStatus
        executed = [bool]$executed
        duplicate_prevented = $false
        timed_out = [bool]$timedOut
        exit_code = $exitCode
        duration_ms = $durationMs
        command_fingerprint = $commandFingerprint
        idempotency_key_sha256 = $idempotencyHash
        working_directory_sha256 = $workingDirectoryHash
        stdout_sha256 = $stdoutHash
        stderr_sha256 = $stderrHash
        stdout_bytes = [System.Text.Encoding]::UTF8.GetByteCount($stdoutText)
        stderr_bytes = [System.Text.Encoding]::UTF8.GetByteCount($stderrText)
        error_code = $errorCode
        error_summary = $errorSummary
    }
    $stage = "event-evidence"
    Write-JsonNoBom -Path $eventPath -Value $event

    $completedIndex = [ordered]@{
        schema = "antigravity-harness-idempotency-index-v2"
        operation_id = $OperationId
        idempotency_key_sha256 = $idempotencyHash
        command_fingerprint = $commandFingerprint
        attempt_count = $attemptNumber
        last_status = $eventStatus
        last_attempt_id = $attemptId
        last_event_path = $eventPath
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $stage = "completion-evidence"
    Write-AtomicJson -Path $indexPath -Value $completedIndex

    [ordered]@{
        schema = "antigravity-harness-safe-command-result-v2"
        status = $eventStatus
        executed = [bool]$executed
        duplicate_prevented = $false
        timed_out = [bool]$timedOut
        exit_code = $exitCode
        operation_id = $OperationId
        attempt_number = $attemptNumber
        duration_ms = $durationMs
        command_fingerprint = $commandFingerprint
        idempotency_key_sha256 = $idempotencyHash
        stdout_sha256 = $stdoutHash
        stderr_sha256 = $stderrHash
        stdout_bytes = $event.stdout_bytes
        stderr_bytes = $event.stderr_bytes
        error_code = $errorCode
        error_summary = $errorSummary
        event_path = $eventPath
    } | ConvertTo-Json -Depth 7 -Compress
} catch {
    [ordered]@{
        schema = "antigravity-harness-safe-command-result-v2"
        status = "error"
        executed = $false
        duplicate_prevented = $false
        timed_out = $false
        exit_code = $null
        operation_id = $OperationId
        error_code = "safe_command_failed_$($stage.Replace('-', '_'))"
        error_summary = "The safe command wrapper failed during $stage before producing a complete tool event."
        error_type = $_.Exception.GetType().Name
        error_detail_sha256 = Get-Sha256Text -Value $_.Exception.Message
        event_path = $null
    } | ConvertTo-Json -Depth 5 -Compress
} finally {
    if ($null -ne $process) {
        $process.Dispose()
    }
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
    }
}
