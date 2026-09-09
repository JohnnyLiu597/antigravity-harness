param(
    [string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

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

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $normalizedPath = [IO.Path]::GetFullPath($Path)
    if ($normalizedPath.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }
    $prefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $normalizedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return "<external>"
    }
    return $normalizedPath.Substring($prefix.Length).Replace('\', '/')
}

$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$candidates = New-Object System.Collections.Generic.List[object]
$seen = @{}

function Add-TestCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Ecosystem,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Runner,
        [AllowEmptyString()][string]$Target = "",
        [Parameter(Mandatory = $true)][string]$CollectionStrategy
    )

    $key = "$Ecosystem|$Kind|$Source|$Target".ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
        return
    }
    $seen[$key] = $true
    $candidates.Add([ordered]@{
        id = $Id
        ecosystem = $Ecosystem
        kind = $Kind
        label = $Label
        source = $Source
        runner = $Runner
        target = $Target
        collection_strategy = $CollectionStrategy
    }) | Out-Null
}

$packagePath = Join-Path $root "package.json"
if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
    try {
        $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $scriptProperties = @()
        if ($package.scripts) {
            $scriptProperties = @($package.scripts.PSObject.Properties)
        }
        foreach ($scriptName in @("test", "test:unit", "test:integration", "test:e2e", "typecheck", "lint", "build")) {
            if ($scriptName -in @($scriptProperties.Name)) {
                $strategy = if ($scriptName -like "test*") { "framework-output" } else { "exit-code" }
                Add-TestCandidate -Id ("node-" + ($scriptName -replace '[^a-z0-9]+', '-').Trim('-')) -Ecosystem "node" -Kind "package-script" -Label ("package.json script: " + $scriptName) -Source "package.json" -Runner "npm" -Target $scriptName -CollectionStrategy $strategy
            }
        }
    } catch {
        Add-TestCandidate -Id "node-package-invalid" -Ecosystem "node" -Kind "invalid-manifest" -Label "package.json could not be parsed" -Source "package.json" -Runner "none" -CollectionStrategy "unavailable"
    }
}

$powerShellTests = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '[\\/](artifacts|\.git|node_modules|\.gemini-trash)[\\/]' -and
            ($_.Name -like "*.Tests.ps1" -or
                ($_.Name -like "test-*.ps1" -and $_.FullName -match '[\\/]harness-evals[\\/]'))
        } |
        Sort-Object FullName
)
foreach ($testFile in $powerShellTests) {
    $relative = Get-RelativePath -Root $root -Path $testFile.FullName
    Add-TestCandidate -Id ("powershell-" + (Get-Sha256Text -Text $relative).Substring(0, 12)) -Ecosystem "powershell" -Kind "script" -Label ("PowerShell test: " + $testFile.Name) -Source $relative -Runner "powershell" -Target $relative -CollectionStrategy "explicit-marker-or-exit"
}

$pythonMarkers = @("pyproject.toml", "pytest.ini", "tox.ini")
$pythonSource = $pythonMarkers |
    Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf } |
    Select-Object -First 1
if (-not $pythonSource -and (Test-Path -LiteralPath (Join-Path $root "tests") -PathType Container)) {
    $pythonTest = Get-ChildItem -LiteralPath (Join-Path $root "tests") -Recurse -File -Filter "test_*.py" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($pythonTest) {
        $pythonSource = "tests"
    }
}
if ($pythonSource) {
    Add-TestCandidate -Id "python-pytest" -Ecosystem "python" -Kind "framework" -Label "pytest test suite" -Source $pythonSource -Runner "python" -Target "pytest" -CollectionStrategy "pytest"
}

$solution = Get-ChildItem -LiteralPath $root -File -Filter "*.sln" -ErrorAction SilentlyContinue | Select-Object -First 1
$testProject = Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*Tests.csproj" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](artifacts|\.git)[\\/]' } |
    Select-Object -First 1
if ($solution -or $testProject) {
    $dotnetSource = if ($solution) {
        Get-RelativePath -Root $root -Path $solution.FullName
    } else {
        Get-RelativePath -Root $root -Path $testProject.FullName
    }
    Add-TestCandidate -Id "dotnet-test" -Ecosystem "dotnet" -Kind "framework" -Label ".NET test surface" -Source $dotnetSource -Runner "dotnet" -Target "test" -CollectionStrategy "framework-output"
}

if (Test-Path -LiteralPath (Join-Path $root "go.mod") -PathType Leaf) {
    Add-TestCandidate -Id "go-test" -Ecosystem "go" -Kind "framework" -Label "Go test surface" -Source "go.mod" -Runner "go" -Target "test" -CollectionStrategy "framework-output"
}

if (Test-Path -LiteralPath (Join-Path $root "Cargo.toml") -PathType Leaf) {
    Add-TestCandidate -Id "rust-cargo-test" -Ecosystem "rust" -Kind "framework" -Label "Cargo test surface" -Source "Cargo.toml" -Runner "cargo" -Target "test" -CollectionStrategy "framework-output"
}

$result = [ordered]@{
    schema = "antigravity-test-surface-v1"
    status = if ($candidates.Count -gt 0) { "detected" } else { "none" }
    project_root_sha256 = Get-Sha256Text -Text $root.ToLowerInvariant()
    candidate_count = $candidates.Count
    candidates = $candidates.ToArray()
}

$result | ConvertTo-Json -Depth 8 -Compress
