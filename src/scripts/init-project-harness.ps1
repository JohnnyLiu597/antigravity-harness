param(
    [string]$Root = (Get-Location).Path,
    [string]$ProjectName = "",
    [string]$PrimaryGoal = "Build and maintain the project",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
if (-not $ProjectName) {
    $ProjectName = Split-Path -Leaf $resolvedRoot
}

$templateRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../templates')).Path

function New-FileFromTemplate {
    param(
        [string]$DestinationPath,
        [string]$TemplateName,
        [hashtable]$Replacements
    )

    $parent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if ((Test-Path -LiteralPath $DestinationPath) -and -not $Force) {
        return @{ path = $DestinationPath; status = "skipped"; reason = "already exists" }
    }

    $templatePath = Join-Path $templateRoot $TemplateName
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template not found: $templatePath"
    }

    $content = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
    foreach ($key in $Replacements.Keys) {
        $content = $content.Replace($key, $Replacements[$key])
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($DestinationPath, $content, $utf8NoBom)
    return @{ path = $DestinationPath; status = "created"; reason = "ok" }
}

function Add-GitIgnoreEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Entries
    )

    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Content -LiteralPath $Path -Encoding UTF8
    } else {
        @()
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($existing)) { $lines.Add([string]$line) | Out-Null }
    $added = $false
    foreach ($entry in $Entries) {
        if ($entry -notin @($lines)) {
            $lines.Add($entry) | Out-Null
            $added = $true
        }
    }
    if ($added -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, (($lines.ToArray() -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
    }
    return $added
}

$replacements = @{
    "{{PROJECT_NAME}}" = $ProjectName
    "{{PRIMARY_GOAL}}" = $PrimaryGoal
    "{{CONSTRAINTS}}" = "- Strictly adhere to project architecture and boundaries.`r`n- Test before claiming completion."
    "{{SUCCESS_CRITERIA}}" = "- Code builds cleanly.`r`n- Tests pass.`r`n- Documentation matches changes."
    "YYYY-MM-DD" = (Get-Date -Format "yyyy-MM-dd")
}

$results = New-Object System.Collections.Generic.List[object]

# 1. mission.md
$results.Add((New-FileFromTemplate -DestinationPath (Join-Path $resolvedRoot "mission.md") -TemplateName "mission.template.md" -Replacements $replacements)) | Out-Null

# 2. CONTEXT.md
$results.Add((New-FileFromTemplate -DestinationPath (Join-Path $resolvedRoot "CONTEXT.md") -TemplateName "CONTEXT.template.md" -Replacements $replacements)) | Out-Null

# 3. .agent/rules.md
$results.Add((New-FileFromTemplate -DestinationPath (Join-Path $resolvedRoot ".agent\rules.md") -TemplateName "agent-rules.template.md" -Replacements $replacements)) | Out-Null
$results.Add((New-FileFromTemplate -DestinationPath (Join-Path $resolvedRoot '.agents/rules/antigravity-harness.md') -TemplateName 'agent-discovery.template.md' -Replacements $replacements)) | Out-Null

# 4. MEMORY.md
$memoryPath = Join-Path $resolvedRoot "MEMORY.md"
if (-not (Test-Path -LiteralPath $memoryPath) -or $Force) {
    $memoryContent = @"
# Memory Index

## Project
- Initialized with Antigravity Harness on $((Get-Date -Format "yyyy-MM-dd")).
- Target repository: $ProjectName

## Active Knowledge
- [Add critical verified facts, dependencies, and environment choices here]
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($memoryPath, $memoryContent, $utf8NoBom)
    $results.Add(@{ path = $memoryPath; status = "created"; reason = "ok" }) | Out-Null
} else {
    $results.Add(@{ path = $memoryPath; status = "skipped"; reason = "already exists" }) | Out-Null
}

# 5. Generated/private ignore boundaries
$gitIgnorePath = Join-Path $resolvedRoot ".gitignore"
$ignoreAdded = Add-GitIgnoreEntries -Path $gitIgnorePath -Entries @(".gemini-trash/", "artifacts/")
$results.Add(@{ path = $gitIgnorePath; status = if ($ignoreAdded) { "updated" } else { "unchanged" }; reason = "v2 generated boundaries" }) | Out-Null

# 6. .gemini-trash/
$trashDir = Join-Path $resolvedRoot ".gemini-trash"
if (-not (Test-Path -LiteralPath $trashDir)) {
    New-Item -ItemType Directory -Force -Path $trashDir | Out-Null
    $gitkeep = Join-Path $trashDir ".gitkeep"
    [System.IO.File]::WriteAllText($gitkeep, "", (New-Object System.Text.UTF8Encoding($false)))
    $results.Add(@{ path = $trashDir; status = "created"; reason = "ok" }) | Out-Null
}

[ordered]@{
    status = "success"
    project_name = $ProjectName
    target_root = $resolvedRoot
    scaffold_files = $results.ToArray()
} | ConvertTo-Json -Depth 5 -Compress
