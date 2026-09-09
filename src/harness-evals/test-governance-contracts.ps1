param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Get-SourceText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required governance surface is missing: $RelativePath"
    }
    return Get-Content -Raw -LiteralPath $path
}

function Assert-Matches {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatches {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

$agents = Get-SourceText "src\AGENTS.md"
$gemini = Get-SourceText "src\GEMINI.md"
$tierOne = Get-SourceText "src\skills\reliable-maker-control\SKILL.md"
$rules = Get-SourceText "src\templates\agent-rules.template.md"
$maker = Get-SourceText "src\agents\maker.md"
$testAuthor = Get-SourceText "src\agents\test-author.md"
$testRunner = Get-SourceText "src\agents\test-runner.md"
$tester = Get-SourceText "src\agents\tester.md"
$reviewer = Get-SourceText "src\agents\reviewer.md"
$toolReliability = Get-SourceText "src\skills\tool-reliability\SKILL.md"
$trajectory = Get-SourceText "src\skills\trajectory-capture\SKILL.md"
$memory = Get-SourceText "src\skills\memory-extract\SKILL.md"
$evalHarness = Get-SourceText "src\skills\eval-harness\SKILL.md"
$orchestrator = Get-SourceText "src\skills\harness-orchestrator\SKILL.md"
$contextGuard = Get-SourceText "src\skills\context-guard\SKILL.md"

$agentLineCount = @($agents -split "`r?`n").Count
if ($agentLineCount -ge 80) {
    throw "src/AGENTS.md must remain under 80 lines; observed $agentLineCount."
}
$geminiLineCount = @($gemini -split "`r?`n").Count
if ($geminiLineCount -gt 45) {
    throw "src/GEMINI.md must remain a small Tier 1 router (<=45 lines); observed $geminiLineCount."
}

$governanceText = @($agents, $gemini, $tierOne, $rules) -join "`n"
Assert-Matches $governanceText "(?i)policy-only" "Governance must label prompt-level controls as policy-only."
Assert-Matches $governanceText "(?i)unverified" "Native surfaces must remain unverified until runtime evidence exists."
Assert-NotMatches $governanceText "(?i)(full governance armor|6 lifecycle hooks|six lifecycle hooks|automatically activates|auto-increase thinking budget)" "Governance still overstates advisory behavior as automatic enforcement."
Assert-Matches $gemini "(?i)reliable-maker-control" "GEMINI.md must route complex work to the Tier 1 skill."
Assert-Matches $gemini "(?i)policy-only.*unverified|unverified.*policy-only" "Tier 1 conditional loading must remain policy-only/unverified."
Assert-NotMatches $gemini "(?m)^### (INIT|PRE_TOOL|POST_TOOL|CHECKPOINT|SHUTDOWN) Policy" "GEMINI.md still contains the full Tier 1 policy pack."
Assert-Matches $tierOne "(?i)five lifecycle policies" "Tier 1 skill must state that there are five lifecycle policies."
foreach ($phase in @("INIT", "PRE_TOOL", "POST_TOOL", "CHECKPOINT", "SHUTDOWN")) {
    Assert-Matches $tierOne ("(?m)^### " + [regex]::Escape($phase) + " Policy") "Tier 1 skill is missing the $phase lifecycle policy."
}

foreach ($state in @("planned", "attempted", "executed", "partial", "passed", "checking", "unverified", "blocked", "verified", "approved")) {
    Assert-Matches $tierOne ('(?i)`' + $state + '`') "Completion Truth state '$state' is missing."
}
Assert-Matches $tierOne '(?is)trusted external checker attestation.*assign.*`verified`|assign.*`verified`.*trusted external checker attestation' "Verified must require trusted external checker attestation."
Assert-Matches $tierOne "(?i)IAS.*advisory" "IAS must be explicitly advisory."
Assert-Matches $tierOne "(?i)must not.*completion|completion.*must not" "IAS must not control completion or approval."
Assert-Matches $contextGuard "(?i)IAS.*advisory" "Context Guard must treat IAS as advisory."
Assert-NotMatches $contextGuard "(?i)IAS\s*<=?\s*3[^`n]*(must stop|forces?|trigger)" "Context Guard still lets IAS alone force a control decision."
Assert-Matches $tierOne "(?i)source fidelity" "Source-backed work must distinguish source fidelity."
Assert-Matches $tierOne "(?i)external truth" "Source-backed work must distinguish external truth."
Assert-Matches $tierOne "(?i)source fidelity.*(not|!=).*external truth|external truth.*(not|!=).*source fidelity" "Source fidelity must not be treated as external truth."
Assert-Matches $tierOne "(?i)Final Claim Set" "Source synthesis must use a Final Claim Set after verification and criticism."

$privateStateText = @($agents, $gemini, $tierOne, $rules, $toolReliability, $trajectory, $memory, $evalHarness, $orchestrator) -join "`n"
Assert-Matches $privateStateText '(?i)\.gemini-private.*marker' ".gemini-private must be described as a marker file."
Assert-Matches $privateStateText '(?i)\$env:USERPROFILE\\\.gemini\\harness-state' "Private state must use the canonical harness-state root."
Assert-NotMatches $privateStateText '(?i)\.gemini-private[\\/](failures|trajectories|evals|orchestrator|\.auto-memory)' ".gemini-private is still being used as a state directory."

Assert-Matches $maker '(?i)must not.*self-verify|must not.*assign `verified`' "Maker must be forbidden from self-verifying."
Assert-Matches $testAuthor "(?i)test files only" "Test Author must be restricted to test files."
Assert-Matches $testAuthor '(?i)must not.*assign `verified`' "Test Author must not assign verified."
Assert-NotMatches $testRunner "(?i)(write_to_file|replace_file_content)" "Test Runner must not have file-edit tools."
Assert-Matches $testRunner "(?i)must not (edit|modify).*(product|source|test).*code" "Test Runner must be forbidden from editing code."
Assert-NotMatches $tester "(?i)(write_to_file|replace_file_content)" "Legacy tester compatibility role must not retain edit tools."
Assert-Matches $reviewer "(?i)actual diff" "Reviewer must inspect the actual diff."
Assert-Matches $reviewer '(?i)must not.*assign `verified`' "Reviewer must not bypass the completion gate."

$loggingText = @($toolReliability, $trajectory, $orchestrator, $rules) -join "`n"
Assert-Matches $loggingText "(?i)safe metadata.*hash|hash.*safe metadata" "Logging must be limited to safe metadata and hashes."
foreach ($forbidden in @("raw prompt", "raw tool input", "raw tool output", "hidden reasoning")) {
    Assert-Matches $loggingText ("(?i)(never|must not|forbid)[^`n]*" + [regex]::Escape($forbidden)) "Logging policy must explicitly forbid $forbidden."
}

$authorityText = @($agents, $gemini, $maker, $reviewer, $orchestrator, $rules) -join "`n"
Assert-Matches $authorityText "(?i)(deploy|deployment).*(publish|release).*user|user.*(deploy|deployment).*(publish|release)" "High-risk deployment and publication authority must remain with the user."

[ordered]@{
    status = "success"
    summary = "Governance contracts are truthful, bounded, privacy-safe, and maker-checker separated."
    line_count = $agentLineCount
    gemini_router_line_count = $geminiLineCount
    cases = @(
        "truthful-policy-semantics",
        "five-lifecycle-policies",
        "completion-truth",
        "ias-advisory-only",
        "canonical-private-state",
        "role-separation",
        "safe-observability",
        "human-release-authority"
    )
} | ConvertTo-Json -Depth 5 -Compress
