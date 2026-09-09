param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$srcRoot = Join-Path $ProjectRoot "src"
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }) | Out-Null
}

function Test-RequiredPath {
    param([string]$RelativePath)

    $path = Join-Path $ProjectRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Check -Name "required:$RelativePath" -Status "passed" -Detail "present"
    } else {
        Add-Check -Name "required:$RelativePath" -Status "failed" -Detail "missing"
    }
}

foreach ($path in @(
    "README.md",
    "UPGRADE_PLAN.md",
    "V2_UPGRADE_PLAN.md",
    "LICENSE",
    "mission.md",
    "CONTEXT.md",
    "MEMORY.md",
    ".gitignore",
    ".gitattributes",
    "deploy\sync-to-runtime.ps1",
    "deploy\sync-from-runtime.ps1",
    "deploy\verify-package.ps1",
    "deploy\test-sync-boundaries.ps1",
    "docs\architecture.md",
    "docs\commands.md",
    "docs\antigravity-surfaces.md",
    "docs\project.md",
    "docs\release.md",
    "docs\testing.md",
    "docs\completion-truth.md",
    "docs\reliability.md",
    "docs\job-state.md",
    "docs\verification-gate.md",
    "docs\v3-hook-probe.md",
    "docs\live-hook-probe-20260906.md",
    "docs\live-sentinel-deny-20260906.md",
    "docs\v3-core-tool-observation.md",
    "docs\live-core-tool-observation-20260908.md",
    "docs\live-host-result-classification-20260908.md",
    "docs\v3-session-task-binding.md",
    "docs\live-session-binding-force-ask-failure-20260908.md",
    "docs\v2-upgrade.md",
    "docs\live-canary-20260904.md",
    "docs\live-canary-20260905.md",
    "docs\evaluation-protocol.md",
    "docs\getting-started.md",
    "tests\getting-started.tests.ps1",
    "docs\observability.md",
    "docs\tool-surface.md",
    "docs\smoke.md",
    "docs\loop.md"
)) {
    Test-RequiredPath -RelativePath $path
}

foreach ($path in @(
    "src\AGENTS.md",
    "src\GEMINI.md",
    "src\harness.capabilities.json",
    "src\harness.components.json",
    "src\agents\maker.md",
    "src\agents\test-author.md",
    "src\agents\test-runner.md",
    "src\schemas\task-contract.schema.json",
    "src\schemas\job-state.schema.json",
    "src\schemas\tool-event.schema.json",
    "src\schemas\completion-claim.schema.json",
    "src\schemas\verification-envelope.schema.json",
    "src\schemas\attempt-ledger.schema.json",
    "src\scripts\verify-manifest-integrity.ps1",
    "src\scripts\audit-governed-execution.ps1",
    "src\scripts\new-governed-task.ps1",
    "src\scripts\new-completion-claim.ps1",
    "src\scripts\audit-desktop-hook-session.ps1",
    "src\scripts\new-desktop-session-binding.ps1",
    "src\desktop-hooks\antigravity-reliable-control\plugin.json",
    "src\desktop-hooks\antigravity-reliable-control\hooks.json",
    "src\desktop-hooks\antigravity-reliable-control\hooks\pre-tool-use.cmd",
    "src\desktop-hooks\antigravity-reliable-control\hooks\pre-tool-use.ps1",
    "src\desktop-hooks\antigravity-reliable-control\hooks\post-tool-use.cmd",
    "src\desktop-hooks\antigravity-reliable-control\hooks\post-tool-use.ps1",
    "src\harness-evals\test-desktop-hook-probe.ps1",
    "deploy\install-desktop-hook-plugin.ps1",
    "src\scripts\audit-harness-components.ps1",
    "src\scripts\probe-native-surfaces.ps1",
    "src\scripts\new-task-contract.ps1",
    "src\scripts\test-task-scope.ps1",
    "src\scripts\new-job-state.ps1",
    "src\scripts\update-job-state.ps1",
    "src\scripts\get-workspace-fingerprint.ps1",
    "src\scripts\invoke-safe-command.ps1",
    "src\scripts\detect-project-test-surface.ps1",
    "src\scripts\invoke-verification-envelope.ps1",
    "src\scripts\invoke-completion-gate.ps1",
    "src\scripts\new-attempt-record.ps1",
    "src\scripts\update-attempt-record.ps1",
    "src\scripts\render-completion-report.ps1",
    "src\skills\reliable-maker-control\SKILL.md",
    "src\harness-evals\run-harness-evals.ps1",
    "src\harness-evals\README.md",
    "src\harness-evals\test-truth-reset.ps1",
    "src\harness-evals\test-control-plane.ps1",
    "src\harness-evals\test-verification-plane.ps1",
    "src\harness-evals\test-governance-contracts.ps1",
    "src\harness-evals\test-package-integration.ps1",
    "src\harness-evals\test-gate-integration.ps1",
    "src\harness-evals\test-project-scaffold-v2.ps1",
    "src\harness-evals\test-attempt-ledger.ps1",
    "src\harness-evals\test-execution-provenance.ps1"
)) {
    $full = Join-Path $ProjectRoot $path
    if (Test-Path -LiteralPath $full) {
        Add-Check -Name "payload:$path" -Status "passed" -Detail "present"
    } else {
        Add-Check -Name "payload:$path" -Status "failed" -Detail "missing"
    }
}

if ((Get-ChildItem -LiteralPath (Join-Path $srcRoot "agents") -File -ErrorAction SilentlyContinue).Count -gt 0) {
    Add-Check -Name "payload:src/agents/" -Status "passed" -Detail "present"
} else {
    Add-Check -Name "payload:src/agents/" -Status "failed" -Detail "missing files"
}

if ((Get-ChildItem -LiteralPath (Join-Path $srcRoot "skills") -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0) {
    Add-Check -Name "payload:src/skills/" -Status "passed" -Detail "present"
} else {
    Add-Check -Name "payload:src/skills/" -Status "failed" -Detail "missing files"
}

if ((Get-ChildItem -LiteralPath (Join-Path $srcRoot "scripts") -File -ErrorAction SilentlyContinue).Count -gt 0) {
    Add-Check -Name "payload:src/scripts/" -Status "passed" -Detail "present"
} else {
    Add-Check -Name "payload:src/scripts/" -Status "failed" -Detail "missing files"
}

if ((Get-ChildItem -LiteralPath (Join-Path $srcRoot "templates") -File -ErrorAction SilentlyContinue).Count -gt 0) {
    Add-Check -Name "payload:src/templates/" -Status "passed" -Detail "present"
} else {
    Add-Check -Name "payload:src/templates/" -Status "failed" -Detail "missing files"
}

if (Test-Path -LiteralPath $srcRoot) {
    $files = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -Force -File -ErrorAction SilentlyContinue)
    $forbidden = @($files | Where-Object {
        $_.Name -in @("auth.json", "config.json", "config.toml", "mcp_config.json", ".gemini-private", ".sync-manifest.json", "installation_id", "feishu-bridge-state.json", "antigravity_state.pbtxt", "skills.txt") -or
        $_.Name -like "*.sqlite*" -or
        $_.Name -like "*.pyc" -or
        $_.Name -like "*.pyo" -or
        $_.Name -like "*.pb" -or
        $_.Name -like "*.pbtxt" -or
        $_.Name -match '(?i)\.bak(?:[-.].*)?$|\.backup(?:[-.].*)?$|~$' -or
        $_.FullName -match '\\(brain|conversations|plugins|cache|sessions|logs|browser-state|\.sandbox[^\\]*|\.tmp|tmp|harness-health|harness-changes|harness-learning|harness-state|antigravity-browser-profile|antigravity-cli|antigravity-ide|sidecar_data|context_state|crashes|html_artifacts)\\'
    })
    if ($forbidden.Count -eq 0) {
        Add-Check -Name "forbidden-runtime-files" -Status "passed" -Detail "none found"
    } else {
        Add-Check -Name "forbidden-runtime-files" -Status "failed" -Detail (($forbidden | Select-Object -First 20 -ExpandProperty FullName) -join "; ")
    }
}

$manifestVerifier = Join-Path $srcRoot "scripts\verify-manifest-integrity.ps1"
if (Test-Path -LiteralPath $manifestVerifier -PathType Leaf) {
    try {
        $manifestResult = & $manifestVerifier -ProjectRoot $ProjectRoot -NoThrow | ConvertFrom-Json
        if ($manifestResult.status -eq "passed") {
            Add-Check -Name "manifest-integrity" -Status "passed" -Detail "capability and component claims are evidence-bound"
        } else {
            Add-Check -Name "manifest-integrity" -Status "failed" -Detail (@($manifestResult.failures) -join "; ")
        }
    } catch {
        Add-Check -Name "manifest-integrity" -Status "failed" -Detail $_.Exception.Message
    }
} else {
    Add-Check -Name "manifest-integrity" -Status "failed" -Detail "verify-manifest-integrity.ps1 missing"
}

$textExtensions = @(".ps1", ".md", ".json", ".txt", ".yaml", ".yml", ".toml", ".py", ".ts", ".js", ".cs")
if (Test-Path -LiteralPath $srcRoot) {
    $textFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in $textExtensions -or -not $_.Extension })
    $leaks = New-Object System.Collections.Generic.List[string]
    foreach ($file in $textFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($null -ne $content) {
            if ($content -match 'C:\\Users\\' -or $content -match 'C:/Users/') { $leaks.Add("$($file.Name): user path leak"); continue }
            if ($content -match '(?i)Johnny(Liu| Liu)?') { $leaks.Add("$($file.Name): username leak"); continue }
            if ($content -match '(?<![a-zA-Z])AIza[0-9A-Za-z_-]{20,}|(?<![a-zA-Z])sk-[a-zA-Z0-9]{20,}|(?<![a-zA-Z])ghp_[a-zA-Z0-9]{20,}|(?<![a-zA-Z])ghu_[a-zA-Z0-9]{20,}|Bearer [a-zA-Z0-9._\-]{20,}') { $leaks.Add("$($file.Name): potential API key leak"); continue }
        }
    }
    if ($leaks.Count -eq 0) {
        Add-Check -Name "leak-scan" -Status "passed" -Detail "no leaks found"
    } else {
        Add-Check -Name "leak-scan" -Status "failed" -Detail ($leaks -join "; ")
    }
}

$psScripts = @()
foreach ($dir in @("deploy", "src")) {
    $full = Join-Path $ProjectRoot $dir
    if (Test-Path -LiteralPath $full) {
        $psScripts += @(Get-ChildItem -LiteralPath $full -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
    }
}

$parseErrors = New-Object System.Collections.Generic.List[string]
foreach ($script in $psScripts) {
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $script.FullName -Raw), [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $parseErrors.Add("$($script.FullName): $($errors[0].Message)") | Out-Null
    }
}
if ($parseErrors.Count -eq 0) {
    Add-Check -Name "powershell-parse" -Status "passed" -Detail "$($psScripts.Count) scripts parsed"
} else {
    Add-Check -Name "powershell-parse" -Status "failed" -Detail ($parseErrors -join "; ")
}

if (Test-Path -LiteralPath $srcRoot) {
    $jsonFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File -Filter "*.json" -ErrorAction SilentlyContinue)
    $jsonErrors = New-Object System.Collections.Generic.List[string]
    foreach ($jsonFile in $jsonFiles) {
        try {
            Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        } catch {
            $jsonErrors.Add("$($jsonFile.Name): $($_.Exception.Message)") | Out-Null
        }
    }
    if ($jsonErrors.Count -eq 0) {
        Add-Check -Name "json-validation" -Status "passed" -Detail "$($jsonFiles.Count) JSON files valid"
    } else {
        Add-Check -Name "json-validation" -Status "failed" -Detail ($jsonErrors -join "; ")
    }
}

$skillRoot = Join-Path $srcRoot "skills"
if (Test-Path -LiteralPath $skillRoot) {
    $skillDirs = @(Get-ChildItem -LiteralPath $skillRoot -Directory -Force)
    $missingSkillMd = @($skillDirs | Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md")) })
    $invalidSkillMd = New-Object System.Collections.Generic.List[string]
    foreach ($skillDir in $skillDirs) {
        $skillPath = Join-Path $skillDir.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($skillPath)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0x2D -or $bytes[1] -ne 0x2D -or $bytes[2] -ne 0x2D) {
            $invalidSkillMd.Add("$($skillDir.Name): SKILL.md must start with --- in UTF-8 without BOM") | Out-Null
            continue
        }
        $skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
        $frontmatter = [regex]::Match($skillText, '\A---\r?\n(?<body>[\s\S]*?)\r?\n---(?:\r?\n|$)')
        if (-not $frontmatter.Success) {
            $invalidSkillMd.Add("$($skillDir.Name): malformed YAML frontmatter or missing closing ---") | Out-Null
            continue
        }
        $metadata = $frontmatter.Groups["body"].Value
        $name = [regex]::Match($metadata, '(?m)^name:\s*["'']?(?<value>[^\r\n"'']+)')
        if (-not $name.Success -or $name.Groups["value"].Value.Trim() -ne $skillDir.Name) {
            $invalidSkillMd.Add("$($skillDir.Name): name metadata is missing or does not match directory") | Out-Null
        }
    }
    if ($missingSkillMd.Count -eq 0 -and $invalidSkillMd.Count -eq 0) {
        Add-Check -Name "skill-frontmatter-surface" -Status "passed" -Detail "$($skillDirs.Count) skill directories have loadable SKILL.md frontmatter"
    } else {
        $details = @($missingSkillMd | ForEach-Object { "$($_.Name): missing SKILL.md" }) + @($invalidSkillMd)
        Add-Check -Name "skill-frontmatter-surface" -Status "failed" -Detail ($details -join "; ")
    }
}

$agentsPath = Join-Path $srcRoot "AGENTS.md"
if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
    $lines = (Get-Content -LiteralPath $agentsPath).Count
    if ($lines -lt 80) {
        Add-Check -Name "agents-md-line-count" -Status "passed" -Detail "$lines lines"
    } else {
        Add-Check -Name "agents-md-line-count" -Status "failed" -Detail "has $lines lines (limit < 80)"
    }
}

$geminiMdPath = Join-Path $srcRoot "GEMINI.md"
if (Test-Path -LiteralPath $geminiMdPath -PathType Leaf) {
    $content = Get-Content -LiteralPath $geminiMdPath -Raw
    if ($content -match 'gemini-3-flash' -or $content -match 'gemini-3\.1-pro') {
        Add-Check -Name "model-references" -Status "failed" -Detail "contains outdated model references"
    } else {
        Add-Check -Name "model-references" -Status "passed" -Detail "no outdated models"
    }
}

$status = if (@($checks | Where-Object { $_.status -eq "failed" }).Count -gt 0) { "failed" } else { "passed" }
$report = [ordered]@{
    schema = "antigravity-harness-package-check-v1"
    status = $status
    created_at = (Get-Date).ToString("o")
    project_root = $ProjectRoot
    checks = $checks.ToArray()
}

$reportDir = Join-Path $ProjectRoot "artifacts\checks"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$reportPath = Join-Path $reportDir ((Get-Date -Format "yyyyMMdd-HHmmss") + "-package-check.json")
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($status -eq "failed") {
    $report | ConvertTo-Json -Depth 8 -Compress | Out-Host
    throw "Package verification failed. See $reportPath"
}

[ordered]@{
    status = "success"
    summary = "Antigravity harness package verified."
    report = $reportPath
} | ConvertTo-Json -Depth 8 -Compress
