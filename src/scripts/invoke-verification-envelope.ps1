param(
    [string]$ProjectRoot = ".",
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$CommandLabel = "verification",
    [string[]]$SourcePaths = @(),
    [string[]]$TestPaths = @(),
    [string[]]$ProtectedPaths = @(),
    [string[]]$AcceptanceCriteria = @(),
    [string]$TestResultPath = "",
    [string]$TaskId = '',
    [string]$TaskAttemptId = '',
    [string]$ContractPath = '',
    [switch]$RequireSourcePaths,
    [switch]$RequireTestPaths,
    [switch]$RequireProtectedPaths,
    [switch]$RequireTestsCollected,
    [switch]$RequireStructuredTestResult,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
Set-StrictMode -Off

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-LineCount {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }
    $trimmed = $Text.TrimEnd([char]13, [char]10)
    if ([string]::IsNullOrEmpty($trimmed)) {
        return 0
    }
    return @($trimmed -split "\r?\n").Count
}

function ConvertTo-SafeText {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateRange(1, 1024)][int]$MaxLength = 160
    )

    $value = [string]$Text
    if ($script:root) {
        $value = $value.Replace($script:root, "<project>")
        $value = $value.Replace(($script:root -replace '\\', '/'), "<project>")
    }
    $value = ($value -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
    if ($value.Length -gt $MaxLength) {
        return $value.Substring(0, $MaxLength)
    }
    return $value
}

function ConvertTo-Slug {
    param([AllowEmptyString()][string]$Value)

    $slug = (([string]$Value).ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug) {
        return $slug
    }
    return "verification"
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    $builder.Append('"') | Out-Null
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            if ($backslashes -gt 0) {
                $builder.Append(('\' * ($backslashes * 2))) | Out-Null
            }
            $builder.Append('\"') | Out-Null
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            $builder.Append(('\' * $backslashes)) | Out-Null
            $backslashes = 0
        }
        $builder.Append($character) | Out-Null
    }
    if ($backslashes -gt 0) {
        $builder.Append(('\' * ($backslashes * 2))) | Out-Null
    }
    $builder.Append('"') | Out-Null
    return $builder.ToString()
}

function Add-FailureCode {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List,
        [Parameter(Mandatory = $true)][string]$Code
    )

    if (-not $List.Contains($Code)) {
        $List.Add($Code) | Out-Null
    }
}

function Resolve-ProjectPathDescriptors {
    param(
        [string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Category
    )

    $items = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $normalizedRoot = [IO.Path]::GetFullPath($script:root).TrimEnd('\', '/')
    $rootPrefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar

    foreach ($inputPath in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$inputPath)) {
            Add-FailureCode -List $script:preflightFailures -Code ("$Category-path-empty")
            continue
        }

        try {
            $candidate = if ([IO.Path]::IsPathRooted([string]$inputPath)) {
                [IO.Path]::GetFullPath([string]$inputPath)
            } else {
                [IO.Path]::GetFullPath((Join-Path $normalizedRoot ([string]$inputPath)))
            }
            $insideRoot = $candidate.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase) -or
                $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
            if (-not $insideRoot) {
                Add-FailureCode -List $script:preflightFailures -Code ("$Category-path-outside-project")
                continue
            }
            $candidate=Get-AgPath $candidate

            $displayPath = if ($candidate.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                "."
            } else {
                $candidate.Substring($rootPrefix.Length).Replace('\', '/')
            }
            $key = $candidate.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $items.Add([pscustomobject]@{
                    full_path = $candidate
                    path = $displayPath
                }) | Out-Null
            }
        } catch {
            Add-FailureCode -List $script:preflightFailures -Code ("$Category-path-invalid")
        }
    }

    return $items.ToArray()
}

function Get-PathDigest {
    param([Parameter(Mandatory = $true)][object]$Descriptor)

    try {
        $null=Get-AgPath $Descriptor.full_path
        if (-not (Test-Path -LiteralPath $Descriptor.full_path)) {
            return [ordered]@{
                path = $Descriptor.path
                type = "missing"
                sha256 = ""
                files = 0
                bytes = 0
            }
        }

        if (Test-Path -LiteralPath $Descriptor.full_path -PathType Leaf) {
            $item = Get-Item -LiteralPath $Descriptor.full_path -Force -ErrorAction Stop
            return [ordered]@{
                path = $Descriptor.path
                type = "file"
                sha256 = (Get-FileHash -LiteralPath $Descriptor.full_path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                files = 1
                bytes = [long]$item.Length
            }
        }

        if (Test-Path -LiteralPath $Descriptor.full_path -PathType Container) {
            $directoryPrefix = $Descriptor.full_path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            $lines = New-Object System.Collections.Generic.List[string]
            $totalBytes = [long]0
            foreach ($file in @(Get-ChildItem -LiteralPath $Descriptor.full_path -Recurse -Force -File -ErrorAction Stop | Sort-Object FullName)) {
                $null=Get-AgPath $file.FullName
                $relative = $file.FullName.Substring($directoryPrefix.Length).Replace('\', '/')
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $lines.Add("$relative|$hash|$([long]$file.Length)") | Out-Null
                $totalBytes += [long]$file.Length
            }
            return [ordered]@{
                path = $Descriptor.path
                type = "directory"
                sha256 = Get-Sha256Text -Text ($lines -join [Environment]::NewLine)
                files = $lines.Count
                bytes = $totalBytes
            }
        }
    } catch {
        return [ordered]@{
            path = $Descriptor.path
            type = "error"
            sha256 = ""
            files = 0
            bytes = 0
        }
    }

    return [ordered]@{
        path = $Descriptor.path
        type = "error"
        sha256 = ""
        files = 0
        bytes = 0
    }
}

function Get-PathDigests {
    param([object[]]$Descriptors)

    return @($Descriptors | ForEach-Object { Get-PathDigest -Descriptor $_ })
}

function Get-AggregateDigest {
    param([object[]]$Digests)

    return Get-Sha256Text -Text (ConvertTo-Json -InputObject @($Digests) -Depth 12 -Compress)
}

function Get-MissingDigestPaths {
    param([object[]]$Digests)

    return @(
        $Digests |
            Where-Object { $_.type -notin @("file", "directory") } |
            ForEach-Object { [string]$_.path }
    )
}

function Compare-DigestSets {
    param(
        [object[]]$Before,
        [object[]]$After
    )

    $changed = New-Object System.Collections.Generic.List[string]
    $beforeByPath = @{}
    $afterByPath = @{}
    foreach ($item in @($Before)) {
        $beforeByPath[[string]$item.path] = $item
    }
    foreach ($item in @($After)) {
        $afterByPath[[string]$item.path] = $item
    }
    foreach ($path in @($beforeByPath.Keys + $afterByPath.Keys | Sort-Object -Unique)) {
        if (-not $beforeByPath.ContainsKey($path) -or -not $afterByPath.ContainsKey($path)) {
            $changed.Add($path) | Out-Null
            continue
        }
        $beforeItem = $beforeByPath[$path]
        $afterItem = $afterByPath[$path]
        if ($beforeItem.type -ne $afterItem.type -or
            $beforeItem.sha256 -ne $afterItem.sha256 -or
            [long]$beforeItem.files -ne [long]$afterItem.files -or
            [long]$beforeItem.bytes -ne [long]$afterItem.bytes) {
            $changed.Add($path) | Out-Null
        }
    }
    return @($changed.ToArray() | Sort-Object -Unique)
}

function Test-GitWorkspace {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return $false
    }
    try {
        $global:LASTEXITCODE = 0
        $value = @(& $git.Source -C $script:root rev-parse --is-inside-work-tree 2>$null)
        return ($LASTEXITCODE -eq 0 -and (($value -join "").Trim()) -eq "true")
    } catch {
        return $false
    }
}

function Get-WorkspaceFingerprint {
    $excludedRoots = @(
        ".git",
        "artifacts",
        "harness-state",
        ".gemini-trash",
        ".codex-trash",
        "node_modules",
        ".venv",
        "venv",
        "__pycache__",
        ".pytest_cache",
        ".mypy_cache",
        ".next",
        "dist",
        "build",
        "coverage"
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $algorithm = "filesystem-content-v1"
    $paths = @()

    if (Test-GitWorkspace) {
        $git = Get-Command git -ErrorAction Stop
        try {
            $global:LASTEXITCODE = 0
            $listed = @(& $git.Source -C $script:root ls-files --cached --others --exclude-standard 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $algorithm = "git-content-v1"
                $paths = @($listed | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
            }
        } catch {
            $paths = @()
        }
    }

    if ($algorithm -eq "filesystem-content-v1") {
        $rootPrefix = $script:root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $paths = @(
            Get-ChildItem -LiteralPath $script:root -Recurse -Force -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $relative = $_.FullName.Substring($rootPrefix.Length).Replace('\', '/')
                    $firstSegment = @($relative -split '/')[0]
                    if ($firstSegment -notin $excludedRoots) {
                        $relative
                    }
                } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
    }

    foreach ($relative in $paths) {
        $fullPath = Join-Path $script:root $relative
        try {
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
                $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                $lines.Add("$($relative.Replace('\', '/'))|$hash|$([long]$item.Length)") | Out-Null
            } else {
                $lines.Add("$($relative.Replace('\', '/'))|missing|0") | Out-Null
            }
        } catch {
            $lines.Add("$($relative.Replace('\', '/'))|error|0") | Out-Null
        }
    }

    return [pscustomobject]@{
        algorithm = $algorithm
        excluded_roots = $excludedRoots
        sha256 = Get-Sha256Text -Text ($lines -join [Environment]::NewLine)
        files = $lines.Count
    }
}

function Get-TestCollectionObservation {
    param([AllowEmptyString()][string]$Text)

    $patterns = @(
        [pscustomobject]@{ source = "explicit-marker"; pattern = '(?im)\btests_collected\s*[:=]\s*(\d+)\b'; group = 1 },
        [pscustomobject]@{ source = "pytest"; pattern = '(?im)\bcollected\s+(\d+)\s+items?\b'; group = 1 },
        [pscustomobject]@{ source = "jest"; pattern = '(?im)^\s*Tests:\s+(?:\d+\s+failed,\s*)?(?:\d+\s+passed,\s*)?(\d+)\s+total\b'; group = 1 },
        [pscustomobject]@{ source = "pester"; pattern = '(?im)\bTotalCount\s*[:=]\s*(\d+)\b'; group = 1 },
        [pscustomobject]@{ source = "generic-passed"; pattern = '(?im)\b(\d+)\s+passed\b'; group = 1 }
    )

    foreach ($entry in $patterns) {
        $match = [regex]::Match([string]$Text, $entry.pattern)
        if ($match.Success) {
            return [pscustomobject]@{
                observed = $true
                count = [int]$match.Groups[$entry.group].Value
                source = $entry.source
            }
        }
    }

    return [pscustomobject]@{
        observed = $false
        count = $null
        source = "not-observed"
    }
}

function Test-CommandBoundToDeclaredTests {
    param(
        [Parameter(Mandatory = $true)][string]$CommandText,
        [object[]]$TestDescriptors
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($CommandText, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { return $false }
    $expectedPaths = @($TestDescriptors | ForEach-Object {
        ([string]$_.path).Replace('\', '/').TrimStart('.', '/')
    })
    $commands = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true))
    foreach ($commandAst in $commands) {
        $commandName = [string]$commandAst.GetCommandName()
        $normalizedCommand = $commandName.Trim().Trim('"', "'").Replace('\', '/').TrimStart('.', '/')
        if ($normalizedCommand -in $expectedPaths) { return $true }

        if ($normalizedCommand -in @("powershell", "powershell.exe", "pwsh", "pwsh.exe")) {
            $elements = @($commandAst.CommandElements | ForEach-Object {
                ([string]$_.Extent.Text).Trim().Trim('"', "'").Replace('\', '/').TrimStart('.', '/')
            })
            for ($index = 0; $index -lt ($elements.Count - 1); $index++) {
                if ($elements[$index] -ieq "-File" -and $elements[$index + 1] -in $expectedPaths) {
                    return $true
                }
            }
        }
    }
    return $false
}

function Test-IsWindows {
    try {
        return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows
        )
    } catch {
        return ($env:OS -eq "Windows_NT")
    }
}

function Get-DescendantProcessIds {
    param([int]$ParentId)

    $descendants = New-Object System.Collections.Generic.List[int]
    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId)
        $pending = New-Object System.Collections.Generic.Queue[int]
        $seen = @{}
        $pending.Enqueue($ParentId)
        $seen[$ParentId] = $true
        while ($pending.Count -gt 0) {
            $current = $pending.Dequeue()
            foreach ($candidate in @($processes | Where-Object { [int]$_.ParentProcessId -eq $current })) {
                $childId = [int]$candidate.ProcessId
                if ($seen.ContainsKey($childId)) {
                    continue
                }
                $seen[$childId] = $true
                $descendants.Add($childId) | Out-Null
                $pending.Enqueue($childId)
            }
        }
    } catch {
    }
    return $descendants.ToArray()
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }
    try {
        $rootProcessId = [int]$Process.Id
    } catch {
        return
    }
    $descendants = @(Get-DescendantProcessIds -ParentId $rootProcessId)

    if (Test-IsWindows) {
        $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
        if ($taskkill) {
            try {
                & $taskkill.Source /PID $rootProcessId /T /F 2>$null | Out-Null
            } catch {
            }
        }
    }

    foreach ($childId in @($descendants | Sort-Object -Descending)) {
        $child = $null
        try {
            $child = [System.Diagnostics.Process]::GetProcessById($childId)
            if (-not $child.HasExited) {
                $child.Kill()
            }
            $child.WaitForExit(5000) | Out-Null
        } catch {
        } finally {
            if ($child) {
                try {
                    $child.Dispose()
                } catch {
                }
            }
        }
    }

    try {
        if (-not $Process.HasExited) {
            $killTreeMethod = $Process.GetType().GetMethod("Kill", [type[]]@([bool]))
            if ($killTreeMethod) {
                $killTreeMethod.Invoke($Process, @($true)) | Out-Null
            } else {
                $Process.Kill()
            }
        }
    } catch {
    }
    try {
        $Process.WaitForExit(5000) | Out-Null
    } catch {
    }
}

function Get-TaskText {
    param([object]$Task)

    if ($null -eq $Task) {
        return ""
    }
    try {
        if ($Task.Wait(5000)) {
            return [string]$Task.Result
        }
    } catch {
    }
    return ""
}

function Remove-OwnedTempDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath($Path)
    $ownedPrefix = Join-Path $tempRoot "antigravity-verification-envelope-"
    if (-not $fullPath.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unowned verification temporary directory."
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-BoundedPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$CommandText,
        [Parameter(Mandatory = $true)][int]$Timeout,
        [Parameter(Mandatory = $true)][string]$TempDirectory
    )

    $runnerPath = Join-Path $TempDirectory "runner.ps1"
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null
    $stdout = ""
    $stderr = ""
    $exitCode = -1
    $timedOut = $false
    $launchFailed = $false
    $started = Get-Date
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
    $runnerLines = @(
        '$ErrorActionPreference = "Stop"',
        'try {',
        ('    $commandText = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String("{0}"))' -f $encodedCommand),
        '    $commandBlock = [ScriptBlock]::Create($commandText)',
        '    $global:LASTEXITCODE = 0',
        '    & $commandBlock',
        '    $invocationSucceeded = $?',
        '    $nativeExitCode = $LASTEXITCODE',
        '    if (-not $invocationSucceeded) { exit 1 }',
        '    if ($null -ne $nativeExitCode -and [int]$nativeExitCode -ne 0) { exit [int]$nativeExitCode }',
        '    exit 0',
        '} catch {',
        '    [Console]::Error.WriteLine($_.Exception.Message)',
        '    exit 1',
        '}'
    )

    try {
        New-Item -ItemType Directory -Force -Path $TempDirectory | Out-Null
        Set-Content -LiteralPath $runnerPath -Value ($runnerLines -join [Environment]::NewLine) -Encoding UTF8

        $powerShellHost = Get-Command powershell.exe -ErrorAction SilentlyContinue
        if (-not $powerShellHost) {
            $powerShellHost = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        }
        if (-not $powerShellHost) {
            throw "No PowerShell executable is available for bounded verification."
        }

        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $powerShellHost.Source
            $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + (ConvertTo-NativeArgument -Value $runnerPath)
            $startInfo.WorkingDirectory = $script:root
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            if (-not $process.Start()) {
                throw "Verification process did not start."
            }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
        } catch {
            $launchFailed = $true
            $stderr = $_.Exception.Message
            if ($process) {
                try {
                    $process.Dispose()
                } catch {
                }
            }
            $process = $null
        }

        if ($process) {
            if (-not $process.WaitForExit($Timeout * 1000)) {
                $timedOut = $true
                Stop-ProcessTree -Process $process
                $exitCode = 124
            } else {
                $process.WaitForExit()
                $process.Refresh()
                $exitCode = [int]$process.ExitCode
            }
        }
    } catch {
        $launchFailed = $true
        $stderr = $_.Exception.Message
    } finally {
        if ($process) {
            try {
                if (-not $process.HasExited) {
                    Stop-ProcessTree -Process $process
                }
            } catch {
            }
        }
        $stdout = Get-TaskText -Task $stdoutTask
        $capturedError = Get-TaskText -Task $stderrTask
        if ($capturedError) {
            if ($stderr) {
                $stderr = $stderr + [Environment]::NewLine + $capturedError
            } else {
                $stderr = $capturedError
            }
        }
        if ($process) {
            try {
                $process.Dispose()
            } catch {
            }
        }
    }

    return [pscustomobject]@{
        stdout = $stdout
        stderr = $stderr
        exit_code = $exitCode
        timed_out = $timedOut
        launch_failed = $launchFailed
        duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}

$script:root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$script:preflightFailures = New-Object System.Collections.Generic.List[string]
$failureCodes = New-Object System.Collections.Generic.List[string]
$startedAt = Get-Date
$attemptId = [guid]::NewGuid().ToString("N")
$stamp = $startedAt.ToUniversalTime().ToString("yyyyMMdd-HHmmssfff")
$id = "$stamp-$(ConvertTo-Slug -Value $Name)-$($attemptId.Substring(0, 12))"
$tempRunDir = Join-Path ([IO.Path]::GetTempPath()) ("antigravity-verification-envelope-" + $attemptId)
$manifestPath = $null
$manifestHashPath = $null
$manifestHash = $null
$pendingFailure = $null

try {
    $sourceDescriptors = @(Resolve-ProjectPathDescriptors -Paths $SourcePaths -Category "source")
    $taskBinding=$null
    if($TaskId -or $TaskAttemptId -or $ContractPath){
        if(-not $TaskId -or -not $TaskAttemptId -or -not $ContractPath){throw 'TaskId, TaskAttemptId and ContractPath must be supplied together.'}
        $contractResolved=if([IO.Path]::IsPathRooted($ContractPath)){[IO.Path]::GetFullPath($ContractPath)}else{[IO.Path]::GetFullPath((Join-Path $script:root $ContractPath))}
        if(-not $contractResolved.StartsWith($script:root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Contract outside project.'}
        $contractResolved=Get-AgPath $contractResolved
        $taskBinding=[ordered]@{task_id=$TaskId;task_attempt_id=$TaskAttemptId;contract_sha256=(Get-FileHash -LiteralPath $contractResolved -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $testDescriptors = @(Resolve-ProjectPathDescriptors -Paths $TestPaths -Category "test")
    $protectedDescriptors = @(Resolve-ProjectPathDescriptors -Paths $ProtectedPaths -Category "protected")
    $normalizedAcceptanceCriteria = @($AcceptanceCriteria | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if (@($normalizedAcceptanceCriteria | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$' }).Count -gt 0) {
        Add-FailureCode -List $script:preflightFailures -Code "acceptance-criterion-invalid"
    }
    $testResultFullPath = $null
    $testResultRelativePath = $null
    if ($TestResultPath) {
        try {
            $candidate = [IO.Path]::GetFullPath((Join-Path $script:root $TestResultPath))
            $rootPrefix = $script:root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "outside" }
            $testResultFullPath = Get-AgPath $candidate
            $testResultRelativePath = $candidate.Substring($rootPrefix.Length).Replace('\', '/')
        } catch {
            Add-FailureCode -List $script:preflightFailures -Code "test-result-path-invalid"
        }
    }
    if (($RequireStructuredTestResult -or $normalizedAcceptanceCriteria.Count -gt 0) -and -not $testResultFullPath) {
        Add-FailureCode -List $script:preflightFailures -Code "structured-test-result-required"
    }

    if ($RequireSourcePaths -and $sourceDescriptors.Count -eq 0) {
        Add-FailureCode -List $script:preflightFailures -Code "required-source-paths-empty"
    }
    if ($RequireTestPaths -and $testDescriptors.Count -eq 0) {
        Add-FailureCode -List $script:preflightFailures -Code "required-test-paths-empty"
    }
    if ($RequireProtectedPaths -and $protectedDescriptors.Count -eq 0) {
        Add-FailureCode -List $script:preflightFailures -Code "required-protected-paths-empty"
    }
    if ($RequireTestsCollected -and $testDescriptors.Count -eq 0) {
        Add-FailureCode -List $script:preflightFailures -Code "test-paths-empty"
    }
    if ($RequireTestsCollected -and $testDescriptors.Count -gt 0 -and
        -not (Test-CommandBoundToDeclaredTests -CommandText $Command -TestDescriptors $testDescriptors)) {
        Add-FailureCode -List $script:preflightFailures -Code "test-command-not-bound"
    }

    $sourceBefore = @(Get-PathDigests -Descriptors $sourceDescriptors)
    $testsBefore = @(Get-PathDigests -Descriptors $testDescriptors)
    $protectedBefore = @(Get-PathDigests -Descriptors $protectedDescriptors)
    $sourceMissingBefore = @(Get-MissingDigestPaths -Digests $sourceBefore)
    $testsMissingBefore = @(Get-MissingDigestPaths -Digests $testsBefore)
    $protectedMissingBefore = @(Get-MissingDigestPaths -Digests $protectedBefore)

    if ($sourceMissingBefore.Count -gt 0) {
        Add-FailureCode -List $script:preflightFailures -Code "source-path-missing"
    }
    if ($testsMissingBefore.Count -gt 0) {
        Add-FailureCode -List $script:preflightFailures -Code "test-path-missing"
    }
    if ($protectedMissingBefore.Count -gt 0) {
        Add-FailureCode -List $script:preflightFailures -Code "protected-path-missing"
    }
    foreach ($preflightFailure in $script:preflightFailures) {
        Add-FailureCode -List $failureCodes -Code $preflightFailure
    }

    $workspaceBefore = Get-WorkspaceFingerprint
    $capture = [pscustomobject]@{
        stdout = ""
        stderr = ""
        exit_code = $null
        timed_out = $false
        launch_failed = $false
        duration_ms = 0
    }
    $execution = "skipped-preflight"

    if ($script:preflightFailures.Count -eq 0) {
        $execution = "ran"
        $capture = Invoke-BoundedPowerShell -CommandText $Command -Timeout $TimeoutSeconds -TempDirectory $tempRunDir
        if ($capture.timed_out) {
            Add-FailureCode -List $failureCodes -Code "process-timeout"
        } elseif ($capture.launch_failed) {
            Add-FailureCode -List $failureCodes -Code "process-launch"
        } elseif ($capture.exit_code -ne 0) {
            Add-FailureCode -List $failureCodes -Code "process-exit"
        }
    }

    $sourceAfter = @(Get-PathDigests -Descriptors $sourceDescriptors)
    $testsAfter = @(Get-PathDigests -Descriptors $testDescriptors)
    $protectedAfter = @(Get-PathDigests -Descriptors $protectedDescriptors)
    $workspaceAfter = Get-WorkspaceFingerprint

    $sourceMissingAfter = @(Get-MissingDigestPaths -Digests $sourceAfter)
    $testsMissingAfter = @(Get-MissingDigestPaths -Digests $testsAfter)
    $protectedMissingAfter = @(Get-MissingDigestPaths -Digests $protectedAfter)
    if ($sourceMissingAfter.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "source-path-missing"
    }
    if ($testsMissingAfter.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "test-path-missing"
    }
    if ($protectedMissingAfter.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "protected-path-missing"
    }

    $sourceChanges = @(Compare-DigestSets -Before $sourceBefore -After $sourceAfter)
    $testChanges = @(Compare-DigestSets -Before $testsBefore -After $testsAfter)
    $stalePaths = @($sourceChanges + $testChanges | Sort-Object -Unique)
    $inputsStale = ($stalePaths.Count -gt 0)
    if ($inputsStale) {
        Add-FailureCode -List $failureCodes -Code "input-stale"
    }

    $protectedChanges = @(Compare-DigestSets -Before $protectedBefore -After $protectedAfter)
    if ($protectedChanges.Count -gt 0) {
        Add-FailureCode -List $failureCodes -Code "protected-path-changed"
    }

    $workspaceChanged = ($workspaceBefore.sha256 -ne $workspaceAfter.sha256)
    if ($workspaceChanged) {
        Add-FailureCode -List $failureCodes -Code "workspace-changed-during-verification"
    }

    $combinedOutput = ([string]$capture.stdout) + [Environment]::NewLine + ([string]$capture.stderr)
    $structuredResult = $null
    $structuredCases = @()
    $passedCaseIds = @()
    $testResultSha256 = $null
    if ($testResultFullPath) {
        if (-not (Test-Path -LiteralPath $testResultFullPath -PathType Leaf)) {
            Add-FailureCode -List $failureCodes -Code "structured-test-result-missing"
        } else {
            try {
                $structuredResult = Get-Content -LiteralPath $testResultFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$structuredResult.schema -ne "antigravity-test-result-v1") { throw "schema" }
                $structuredCases = @($structuredResult.cases)
                if (@($structuredCases | Where-Object { $_.status -ne 'passed' }).Count -gt 0) { Add-FailureCode -List $failureCodes -Code 'structured-results-not-passed' }
                if ((Get-Item -LiteralPath $testResultFullPath).LastWriteTimeUtc -lt $startedAt.ToUniversalTime()) { Add-FailureCode -List $failureCodes -Code 'structured-test-result-stale' }
                $invalidCase = @($structuredCases | Where-Object {
                    [string]::IsNullOrWhiteSpace([string]$_.id) -or [string]$_.status -notin @("passed", "failed", "skipped")
                })
                if ($invalidCase.Count -gt 0) { throw "case" }
                $passedCaseIds = @($structuredCases | Where-Object { $_.status -eq "passed" } | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
                $testResultSha256 = (Get-FileHash -LiteralPath $testResultFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            } catch {
                Add-FailureCode -List $failureCodes -Code "structured-test-result-invalid"
            }
        }
    }
    foreach ($criterion in $normalizedAcceptanceCriteria) {
        if ($criterion -notin $passedCaseIds) {
            Add-FailureCode -List $failureCodes -Code "acceptance-criterion-not-passed"
        }
    }

    $testObservation = if ($structuredResult) {
        [pscustomobject]@{ observed = $true; count = $structuredCases.Count; source = "structured-result" }
    } else {
        Get-TestCollectionObservation -Text $combinedOutput
    }
    if ($RequireTestsCollected) {
        if (-not $testObservation.observed) {
            Add-FailureCode -List $failureCodes -Code "tests-collected-unknown"
        } elseif ([int]$testObservation.count -le 0) {
            Add-FailureCode -List $failureCodes -Code "zero-tests-collected"
        }
    }

    $requirementsSatisfied = (
        $script:preflightFailures.Count -eq 0 -and
        $sourceMissingAfter.Count -eq 0 -and
        $testsMissingAfter.Count -eq 0 -and
        $protectedMissingAfter.Count -eq 0
    )
    $status = if ($failureCodes.Count -eq 0) { "passed" } else { "failed" }
    if($taskBinding -and (Get-FileHash -LiteralPath $contractResolved -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskBinding.contract_sha256){Add-FailureCode -List $failureCodes -Code 'contract-changed';$status='failed'}

    $manifest = [ordered]@{
        schema = "antigravity-verification-envelope-v2"
        task_binding = $taskBinding
        id = $id
        attempt_id = $attemptId
        name = ConvertTo-SafeText -Text $Name
        status = $status
        created_at = $startedAt.ToUniversalTime().ToString("o")
        completed_at = (Get-Date).ToUniversalTime().ToString("o")
        project = [ordered]@{
            name = ConvertTo-SafeText -Text (Split-Path -Leaf $script:root)
            root_sha256 = Get-Sha256Text -Text $script:root.ToLowerInvariant()
        }
        command = [ordered]@{
            label = ConvertTo-SafeText -Text $CommandLabel
            sha256 = Get-Sha256Text -Text $Command
            execution = $execution
            exit_code = $capture.exit_code
            timed_out = [bool]$capture.timed_out
            launch_failed = [bool]$capture.launch_failed
            duration_ms = [int]$capture.duration_ms
            timeout_seconds = $TimeoutSeconds
            output_sha256 = Get-Sha256Text -Text $combinedOutput
            output_lines = (Get-LineCount -Text $capture.stdout) + (Get-LineCount -Text $capture.stderr)
            stdout_sha256 = Get-Sha256Text -Text $capture.stdout
            stdout_lines = Get-LineCount -Text $capture.stdout
            stderr_sha256 = Get-Sha256Text -Text $capture.stderr
            stderr_lines = Get-LineCount -Text $capture.stderr
        }
        tests = [ordered]@{
            require_collection = [bool]$RequireTestsCollected
            collection_observed = [bool]$testObservation.observed
            collected_count = $testObservation.count
            collection_source = $testObservation.source
            structured_required = [bool]$RequireStructuredTestResult
            result_path = $testResultRelativePath
            result_sha256 = $testResultSha256
            result_schema = if ($structuredResult) { [string]$structuredResult.schema } else { $null }
            case_results = $structuredCases
            passed_case_ids = $passedCaseIds
        }
        acceptance_criteria = $normalizedAcceptanceCriteria
        requirements = [ordered]@{
            source_paths = [ordered]@{
                required = [bool]$RequireSourcePaths
                declared_count = $sourceDescriptors.Count
                missing = @($sourceMissingBefore + $sourceMissingAfter | Sort-Object -Unique)
            }
            test_paths = [ordered]@{
                required = [bool]$RequireTestPaths
                declared_count = $testDescriptors.Count
                missing = @($testsMissingBefore + $testsMissingAfter | Sort-Object -Unique)
            }
            protected_paths = [ordered]@{
                required = [bool]$RequireProtectedPaths
                declared_count = $protectedDescriptors.Count
                missing = @($protectedMissingBefore + $protectedMissingAfter | Sort-Object -Unique)
            }
            satisfied = [bool]$requirementsSatisfied
        }
        inputs = [ordered]@{
            before = [ordered]@{
                source = $sourceBefore
                source_sha256 = Get-AggregateDigest -Digests $sourceBefore
                tests = $testsBefore
                tests_sha256 = Get-AggregateDigest -Digests $testsBefore
            }
            after = [ordered]@{
                source = $sourceAfter
                source_sha256 = Get-AggregateDigest -Digests $sourceAfter
                tests = $testsAfter
                tests_sha256 = Get-AggregateDigest -Digests $testsAfter
            }
            stale = [bool]$inputsStale
            stale_paths = $stalePaths
        }
        protected = [ordered]@{
            before = $protectedBefore
            before_sha256 = Get-AggregateDigest -Digests $protectedBefore
            after = $protectedAfter
            after_sha256 = Get-AggregateDigest -Digests $protectedAfter
            changed = ($protectedChanges.Count -gt 0)
            changed_paths = $protectedChanges
        }
        workspace = [ordered]@{
            algorithm = $workspaceAfter.algorithm
            excluded_roots = $workspaceAfter.excluded_roots
            before_sha256 = $workspaceBefore.sha256
            before_files = $workspaceBefore.files
            after_sha256 = $workspaceAfter.sha256
            after_files = $workspaceAfter.files
            changed = [bool]$workspaceChanged
        }
        failures = $failureCodes.ToArray()
        script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $runDir = Join-Path $script:root ("artifacts\verification-envelopes\" + $id)
    $null=Get-AgPath $runDir
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $manifestPath = Join-Path $runDir "envelope.json"
    $manifestHashPath = Join-Path $runDir "envelope.sha256"
    $manifest | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $manifestHashPath -Value $manifestHash -Encoding ASCII

    if ($status -eq "failed") {
        $pendingFailure = "Verification envelope failed. Evidence: $manifestPath"
    }
} finally {
    Remove-OwnedTempDirectory -Path $tempRunDir
}

if ($pendingFailure) {
    throw $pendingFailure
}

[ordered]@{
    status = "success"
    summary = "Verification envelope passed."
    id = $id
    attempt_id = $attemptId
    manifest = $manifestPath
    manifest_sha256 = $manifestHash
    manifest_hash_file = $manifestHashPath
    artifacts = @($manifestPath, $manifestHashPath)
} | ConvertTo-Json -Depth 8 -Compress
