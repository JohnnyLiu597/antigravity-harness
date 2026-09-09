param(
    [string]$ProjectRoot = ".",
    [string]$Name = "learning-intake",
    [string]$Source = "manual",
    [string]$Route = "docs",
    [string]$Summary = "",
    [string]$FailureMode = "",
    [string[]]$Evidence = @(),
    [string[]]$NextActions = @()
)

$ErrorActionPreference = "Stop"

$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$intakeDir = Join-Path $root "artifacts\learning-intakes"
New-Item -ItemType Directory -Force -Path $intakeDir | Out-Null

function ConvertTo-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "learning" }
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "learning" }
    return $slug
}

$slug = ConvertTo-Slug -Value $Name
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$filePath = Join-Path $intakeDir "$stamp-$slug.json"

$validRoutes = @("rule", "skill", "eval", "docs", "component")
$resolvedRoute = if ($Route.ToLowerInvariant() -in $validRoutes) { $Route.ToLowerInvariant() } else { "docs" }

$record = [ordered]@{
    schema = "antigravity-harness-learning-intake-v1"
    id = "$stamp-$slug"
    timestamp = (Get-Date).ToString("o")
    name = $Name
    source = $Source
    route = $resolvedRoute
    summary = $Summary
    failure_mode = $FailureMode
    evidence = $Evidence
    next_actions = $NextActions
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$json = $record | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($filePath, $json, $utf8NoBom)

[ordered]@{
    status = "success"
    intake_id = "$stamp-$slug"
    path = $filePath
    route = $resolvedRoute
} | ConvertTo-Json -Depth 4 -Compress
