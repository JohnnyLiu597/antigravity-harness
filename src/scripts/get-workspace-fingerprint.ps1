param(
    [string]$ProjectRoot = ".",
    [string[]]$IncludePaths = @("."),
    [string[]]$ExcludePaths = @(
        ".git/",
        "artifacts/",
        "harness-state/",
        ".gemini-trash/",
        ".codex-trash/",
        "node_modules/"
    ),
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-NormalizedRelativePath {
    param(
        [string]$Root,
        [string]$FullPath
    )
    $rootPrefix = $Root.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the project root: $FullPath"
    }
    return $FullPath.Substring($rootPrefix.Length).Replace("\", "/")
}

function Test-ExcludedPath {
    param(
        [string]$RelativePath,
        [string[]]$Rules
    )
    foreach ($ruleValue in $Rules) {
        if ([string]::IsNullOrWhiteSpace($ruleValue)) { continue }
        $rule = $ruleValue.Replace("\", "/").Trim()
        while ($rule.StartsWith("./", [System.StringComparison]::Ordinal)) {
            $rule = $rule.Substring(2)
        }
        $rule = $rule.TrimStart('/').TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($rule)) { continue }
        if ($RelativePath.Equals($rule, [System.StringComparison]::OrdinalIgnoreCase) -or
            $RelativePath.StartsWith($rule + "/", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-SafeFiles {
    param([string]$StartPath)

    $found = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    if (Test-Path -LiteralPath $StartPath -PathType Leaf) {
        $item = Get-Item -LiteralPath $StartPath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            $found.Add($item) | Out-Null
        }
        return $found.ToArray()
    }

    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($StartPath)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                $found.Add($item) | Out-Null
            }
        }
    }
    return $found.ToArray()
}

function Write-JsonNoBom {
    param(
        [string]$Path,
        $Value
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), $encoding)
}

try {
    $root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName.TrimEnd("\", "/")
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $uniqueFiles = New-Object 'System.Collections.Generic.Dictionary[string,System.IO.FileInfo]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($include in $IncludePaths) {
        if ([string]::IsNullOrWhiteSpace($include)) { continue }
        $candidate = if ([System.IO.Path]::IsPathRooted($include)) {
            [System.IO.Path]::GetFullPath($include)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $root $include))
        }
        if (-not ($candidate.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
                  $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            throw "Include path escapes the project root: $include"
        }
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Include path does not exist: $include"
        }

        foreach ($file in @(Get-SafeFiles -StartPath $candidate)) {
            $relative = Get-NormalizedRelativePath -Root $root -FullPath $file.FullName
            if (Test-ExcludedPath -RelativePath $relative -Rules $ExcludePaths) { continue }
            if (-not $uniqueFiles.ContainsKey($file.FullName)) {
                $uniqueFiles.Add($file.FullName, $file)
            }
        }
    }

    $entries = New-Object System.Collections.Generic.List[string]
    $totalBytes = [int64]0
    foreach ($file in @($uniqueFiles.Values | Sort-Object FullName)) {
        $relative = Get-NormalizedRelativePath -Root $root -FullPath $file.FullName
        $contentHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $length = [int64](Get-Item -LiteralPath $file.FullName -Force).Length
        $totalBytes += $length
        $entries.Add(($relative + "`0" + $length + "`0" + $contentHash)) | Out-Null
    }

    $fingerprint = Get-Sha256Text -Value (($entries.ToArray()) -join "`n")
    $gitCommit = $null
    $gitDirty = $null
    $git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $git) {
        $commitOutput = @(& $git.Source -C $root rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $commitOutput.Count -gt 0) {
            $gitCommit = $commitOutput[0].ToString().Trim()
            $statusOutput = @(& $git.Source -C $root status --porcelain=v1 --untracked-files=all 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $gitDirty = $statusOutput.Count -gt 0
            }
        }
    }

    $result = [ordered]@{
        schema = "antigravity-harness-workspace-fingerprint-v2"
        status = "success"
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        fingerprint_sha256 = $fingerprint
        file_count = $uniqueFiles.Count
        total_bytes = $totalBytes
        git_commit = $gitCommit
        git_dirty = $gitDirty
        excluded_paths = @($ExcludePaths)
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
        Write-JsonNoBom -Path $resolvedOutput -Value $result
    }
    $result | ConvertTo-Json -Depth 6 -Compress
} catch {
    [ordered]@{
        schema = "antigravity-harness-workspace-fingerprint-v2"
        status = "error"
        error_code = "workspace_fingerprint_failed"
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 4 -Compress
}
