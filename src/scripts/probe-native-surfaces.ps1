param(
    [string]$ProjectRoot = ".",
    [string]$RuntimeRoot = ""
)

$ErrorActionPreference = "Stop"
$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
if (-not $RuntimeRoot) {
    $RuntimeRoot = Join-Path $env:USERPROFILE ".gemini"
}

function Get-Sha256Text {
    param([AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$commands = New-Object System.Collections.Generic.List[object]
foreach ($name in @("gemini", "antigravity")) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    $commands.Add([pscustomobject]@{
        name = $name
        available = [bool]$command
        source_sha256 = if ($command) { Get-Sha256Text -Value ([string]$command.Source).ToLowerInvariant() } else { $null }
    }) | Out-Null
}

$runtimeFiles = New-Object System.Collections.Generic.List[object]
foreach ($name in @("AGENTS.md", "GEMINI.md", "harness.capabilities.json", "harness.components.json")) {
    $sourcePath = Join-Path (Join-Path $root "src") $name
    $runtimePath = Join-Path $RuntimeRoot $name
    $sourceExists = Test-Path -LiteralPath $sourcePath -PathType Leaf
    $runtimeExists = Test-Path -LiteralPath $runtimePath -PathType Leaf
    $runtimeFiles.Add([pscustomobject]@{
        name = $name
        source_exists = $sourceExists
        runtime_exists = $runtimeExists
        hashes_match = [bool]($sourceExists -and $runtimeExists -and
            ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -eq
             (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash))
    }) | Out-Null
}

$surfaces = @(
    "ask_question",
    "planning_mode",
    "manage_task",
    "schedule",
    "invoke_subagent",
    "send_message",
    "reactive_wakeup",
    "model_routing"
) | ForEach-Object {
    [pscustomobject]@{
        name = $_
        availability = "unverified"
        evidence = $null
        verification_route = "live Antigravity canary required"
    }
}

[ordered]@{
    schema = "antigravity-native-surface-probe-v2"
    status = "success"
    probe_mode = "static"
    project = [ordered]@{ name = Split-Path -Leaf $root; root_sha256 = Get-Sha256Text -Value $root.ToLowerInvariant() }
    runtime = [ordered]@{ label = '$env:USERPROFILE\.gemini'; root_sha256 = Get-Sha256Text -Value ([System.IO.Path]::GetFullPath($RuntimeRoot).ToLowerInvariant()) }
    commands = $commands.ToArray()
    runtime_files = $runtimeFiles.ToArray()
    surfaces = @($surfaces)
    limitations = @(
        "Static PowerShell inspection cannot prove in-app Antigravity tools or model routing.",
        "No native surface is marked available without live canary evidence."
    )
} | ConvertTo-Json -Depth 8 -Compress
