param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ContractPath,
    [string[]]$ChangedPaths = @(),
    [ValidateRange(0, 2147483647)]
    [int]$AddedLines = 0,
    [switch]$ObserveWorkspace,
    [switch]$DependencyChanged,
    [switch]$ArchitectureChanged
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-NormalizedRelativePath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Changed paths cannot be empty."
    }
    $candidate = $Value.Trim()
    if ([System.IO.Path]::IsPathRooted($candidate) -or $candidate -match '^[A-Za-z]:') {
        throw "Changed path must be project-relative: $Value"
    }
    $candidate = $candidate.Replace("\", "/")
    while ($candidate.StartsWith("./", [System.StringComparison]::Ordinal)) {
        $candidate = $candidate.Substring(2)
    }
    $candidate = $candidate -replace '/+', '/'
    $segments = @($candidate.Split('/') | Where-Object { $_ -ne "" -and $_ -ne "." })
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq ".." }).Count -gt 0) {
        throw "Changed path cannot be empty or traverse outside the project: $Value"
    }
    if (@($segments | Where-Object { $_ -match ':' }).Count -gt 0) {
        throw "Changed path contains an invalid drive or stream separator: $Value"
    }
    return ($segments -join "/")
}

function Test-PathRuleMatch {
    param(
        [string]$Path,
        [string]$Rule
    )

    $normalizedRule = $Rule.Replace("\", "/").Trim()
    while ($normalizedRule.StartsWith("./", [System.StringComparison]::Ordinal)) {
        $normalizedRule = $normalizedRule.Substring(2)
    }
    $normalizedRule = $normalizedRule.TrimEnd('/')
    if ($normalizedRule -eq "." -or [string]::IsNullOrWhiteSpace($normalizedRule)) {
        return $true
    }
    if ($Path.Equals($normalizedRule, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $Path.StartsWith($normalizedRule + "/", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-WorkspaceSnapshot {
    param([string]$Root, [string[]]$ExcludedRoots)
    $prefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $relative = $_.FullName.Substring($prefix.Length).Replace('\', '/')
                if (@($relative -split '/')[0] -in $ExcludedRoots) { return }
                $lineCount = 0
                try { $lineCount = @(Get-Content -LiteralPath $_.FullName -Encoding UTF8 -ErrorAction Stop).Count } catch {}
                [pscustomobject]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); lines = $lineCount }
            } | Sort-Object path
    )
}

try {
    $resolvedContractPath = (Resolve-Path -LiteralPath $ContractPath).Path
    $contract = Get-Content -LiteralPath $resolvedContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($contract.schema -ne "antigravity-harness-task-contract-v2") {
        throw "Unsupported task contract schema: $($contract.schema)"
    }

    $metricSource = "caller-declared"
    if ($ObserveWorkspace) {
        if (-not $contract.baseline -or -not $contract.scope.project_root) { throw "Task contract does not contain an observable baseline." }
        $projectRoot = (Get-Item -LiteralPath (Resolve-Path -LiteralPath ([string]$contract.scope.project_root)).Path -Force).FullName
        $before = @($contract.baseline.files)
        $after = @(Get-WorkspaceSnapshot -Root $projectRoot -ExcludedRoots @($contract.baseline.excluded_roots))
        $beforeMap = @{}; foreach ($item in $before) { $beforeMap[[string]$item.path] = $item }
        $afterMap = @{}; foreach ($item in $after) { $afterMap[[string]$item.path] = $item }
        $observedPaths = New-Object System.Collections.Generic.List[string]
        $observedAddedLines = 0
        foreach ($path in @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)) {
            $beforeItem = if ($beforeMap.ContainsKey($path)) { $beforeMap[$path] } else { $null }
            $afterItem = if ($afterMap.ContainsKey($path)) { $afterMap[$path] } else { $null }
            if (-not $beforeItem -or -not $afterItem -or [string]$beforeItem.sha256 -ne [string]$afterItem.sha256) {
                $observedPaths.Add($path) | Out-Null
                if ($afterItem) {
                    $beforeLines = if ($beforeItem) { [int]$beforeItem.lines } else { 0 }
                    $observedAddedLines += [Math]::Max(0, [int]$afterItem.lines - $beforeLines)
                }
            }
        }
        $ChangedPaths = $observedPaths.ToArray()
        $AddedLines = $observedAddedLines
        $metricSource = "contract-baseline"
    }

    $violations = New-Object System.Collections.Generic.List[object]
    $requiredTriggers = New-Object System.Collections.Generic.List[string]

    function Add-Violation {
        param(
            [string]$Type,
            [string]$Message,
            [string]$Path = "",
            [string]$ApprovalTrigger = "scope_expansion"
        )
        $violations.Add([pscustomobject]@{
            type = $Type
            path = if ([string]::IsNullOrWhiteSpace($Path)) { $null } else { $Path }
            message = $Message
            approval_trigger = $ApprovalTrigger
        }) | Out-Null
        if ($ApprovalTrigger -notin @($requiredTriggers)) {
            $requiredTriggers.Add($ApprovalTrigger) | Out-Null
        }
    }

    $normalizedChanged = New-Object System.Collections.Generic.List[string]
    foreach ($path in $ChangedPaths) {
        try {
            $normalized = ConvertTo-NormalizedRelativePath -Value $path
            if ($normalized -notin @($normalizedChanged)) {
                $normalizedChanged.Add($normalized) | Out-Null
            }
        } catch {
            Add-Violation -Type "invalid_path" -Path $path -Message $_.Exception.Message
        }
    }

    if ($contract.scope.access -eq "read_only" -and $normalizedChanged.Count -gt 0) {
        Add-Violation -Type "read_only_contract" -Message "The contract does not authorize workspace writes."
    }

    $allowedRules = @($contract.scope.allowed_paths)
    $deniedRules = @($contract.scope.denied_paths)
    foreach ($path in $normalizedChanged) {
        $denied = $false
        foreach ($rule in $deniedRules) {
            if (Test-PathRuleMatch -Path $path -Rule $rule) {
                $denied = $true
                break
            }
        }
        if ($denied) {
            Add-Violation -Type "denied_path" -Path $path -Message "The changed path is explicitly denied."
            continue
        }

        $allowed = $false
        foreach ($rule in $allowedRules) {
            if (Test-PathRuleMatch -Path $path -Rule $rule) {
                $allowed = $true
                break
            }
        }
        if (-not $allowed) {
            Add-Violation -Type "outside_allowed_paths" -Path $path -Message "The changed path is outside the contract allowlist."
        }
    }

    if ($normalizedChanged.Count -gt [int]$contract.change_budget.max_files) {
        Add-Violation -Type "max_files_exceeded" -Message "Changed file count $($normalizedChanged.Count) exceeds budget $($contract.change_budget.max_files)."
    }
    if ($AddedLines -gt [int]$contract.change_budget.max_added_lines) {
        Add-Violation -Type "max_added_lines_exceeded" -Message "Added line count $AddedLines exceeds budget $($contract.change_budget.max_added_lines)."
    }
    if ($DependencyChanged -and -not [bool]$contract.change_budget.dependency_changes) {
        Add-Violation -Type "dependency_change_denied" -Message "Dependency changes are not authorized by the contract." -ApprovalTrigger "dependency_change"
    }
    if ($ArchitectureChanged -and -not [bool]$contract.change_budget.architecture_changes) {
        Add-Violation -Type "architecture_change_denied" -Message "Architecture changes are not authorized by the contract." -ApprovalTrigger "architecture_change"
    }

    $isAllowed = $violations.Count -eq 0
    [ordered]@{
        status = if ($isAllowed) { "passed" } else { "waiting_approval" }
        allowed = $isAllowed
        contract_id = $contract.contract_id
        assessment_mode = if ($ObserveWorkspace) { "post_write_observed" } else { "pre_write_declared" }
        metrics = [ordered]@{
            source = $metricSource
            changed_files = $normalizedChanged.Count
            changed_paths = $normalizedChanged.ToArray()
            added_lines = $AddedLines
            dependency_changed = [bool]$DependencyChanged
            architecture_changed = [bool]$ArchitectureChanged
        }
        violations = $violations.ToArray()
        required_approval_triggers = @($requiredTriggers | Sort-Object -Unique)
    } | ConvertTo-Json -Depth 8 -Compress
} catch {
    [ordered]@{
        status = "error"
        allowed = $false
        error_code = "scope_validation_failed"
        error = $_.Exception.Message
        violations = @()
        required_approval_triggers = @()
    } | ConvertTo-Json -Depth 5 -Compress
}
