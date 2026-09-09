param(
    [string]$ProjectRoot = ".",
    [int]$AgentsLineBudget = 80,
    [int]$GeminiLineBudget = 300,
    [int]$SkillLineBudget = 200,
    [int]$AgentLineBudget = 250,
    [int]$MemoryLineBudget = 200
)

$ErrorActionPreference = "Stop"

$root = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectRoot).Path -Force).FullName
$warnings = New-Object System.Collections.Generic.List[string]
$fileRecords = New-Object System.Collections.Generic.List[object]

function Measure-BudgetFile {
    param(
        [string]$Path,
        [string]$Category,
        [int]$MaxLines
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $lines = if ($content) { ($content -split "`r`n|`n|`r").Count } else { 0 }
    $bytes = (Get-Item -LiteralPath $Path).Length
    $relPath = $Path.Replace($root, '').TrimStart('\', '/')

    $status = "ok"
    if ($lines -gt $MaxLines) {
        $status = "exceeded"
        $warnings.Add("$relPath ($lines lines) exceeds budget of $MaxLines lines") | Out-Null
    }

    $fileRecords.Add([pscustomobject]@{
        path = $relPath
        category = $Category
        lines = $lines
        bytes = $bytes
        budget_lines = $MaxLines
        status = $status
    }) | Out-Null
}

# 1. Core rules
Measure-BudgetFile -Path (Join-Path $root "src\AGENTS.md") -Category "baseline-rules" -MaxLines $AgentsLineBudget
Measure-BudgetFile -Path (Join-Path $root "src\GEMINI.md") -Category "runtime-config" -MaxLines $GeminiLineBudget

# 2. Context anchors
Measure-BudgetFile -Path (Join-Path $root "mission.md") -Category "anchor" -MaxLines 100
Measure-BudgetFile -Path (Join-Path $root "CONTEXT.md") -Category "anchor" -MaxLines 100
Measure-BudgetFile -Path (Join-Path $root "MEMORY.md") -Category "anchor" -MaxLines $MemoryLineBudget

# 3. Skills
$skillMds = Get-ChildItem -Path (Join-Path $root "src\skills") -Recurse -Filter "SKILL.md" -ErrorAction SilentlyContinue
foreach ($s in $skillMds) {
    Measure-BudgetFile -Path $s.FullName -Category "skill" -MaxLines $SkillLineBudget
}

# 4. Agents
$agentMds = Get-ChildItem -Path (Join-Path $root "src\agents") -Filter "*.md" -ErrorAction SilentlyContinue
foreach ($a in $agentMds) {
    Measure-BudgetFile -Path $a.FullName -Category "agent" -MaxLines $AgentLineBudget
}

$totalLines = ($fileRecords | Measure-Object -Property lines -Sum).Sum
$totalBytes = ($fileRecords | Measure-Object -Property bytes -Sum).Sum

[ordered]@{
    status = if ($warnings.Count -eq 0) { "passed" } else { "warning" }
    project_root = $root
    total_files = $fileRecords.Count
    total_lines = $totalLines
    total_bytes = $totalBytes
    warnings = $warnings.ToArray()
    records = $fileRecords.ToArray()
} | ConvertTo-Json -Depth 6 -Compress
