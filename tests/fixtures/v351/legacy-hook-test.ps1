# Historical v3.5.1 regression source, preserved verbatim below; not a v4 acceptance owner.
param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path }

$pluginRoot = Join-Path $ProjectRoot "src\desktop-hooks\antigravity-reliable-control"
$pluginManifest = Join-Path $pluginRoot "plugin.json"
$hooksManifest = Join-Path $pluginRoot "hooks.json"
$hookScript = Join-Path $pluginRoot "hooks\pre-tool-use.ps1"
$hookWrapper = Join-Path $pluginRoot "hooks\pre-tool-use.cmd"
$postHookScript = Join-Path $pluginRoot "hooks\post-tool-use.ps1"
$postHookWrapper = Join-Path $pluginRoot "hooks\post-tool-use.cmd"
$installer = Join-Path $ProjectRoot "deploy\install-desktop-hook-plugin.ps1"
$sessionAudit = Join-Path $ProjectRoot "src\scripts\audit-desktop-hook-session.ps1"
$newSessionBinding = Join-Path $ProjectRoot "src\scripts\new-desktop-session-binding.ps1"
$coreMatcher = "list_dir|view_file|write_to_file|replace_file_content|multi_replace_file_content|run_command|invoke_subagent|manage_subagents"

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string]$Message) { if ($Actual -ne $Expected) { throw "$Message (expected '$Expected', got '$Actual')" } }
function Invoke-HookProcess([string]$InputText, [string]$StateRoot, [string]$ScriptPath = $hookScript, [string]$BindingStateRoot = "", [string]$BindingPolicyRoot = "") {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["ANTIGRAVITY_HOOK_PROBE_STATE_ROOT"] = $StateRoot
    if ($BindingStateRoot) { $psi.EnvironmentVariables["ANTIGRAVITY_HOOK_BINDING_STATE_ROOT"] = $BindingStateRoot }
    if ($BindingPolicyRoot) { $psi.EnvironmentVariables["ANTIGRAVITY_HOOK_BINDING_POLICY_ROOT"] = $BindingPolicyRoot }
    $process = [Diagnostics.Process]::Start($psi)
    $process.StandardInput.Write($InputText)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{exit_code=$process.ExitCode;stdout=$stdout;stderr=$stderr}
}

foreach ($path in @($pluginManifest, $hooksManifest, $hookScript, $hookWrapper, $postHookScript, $postHookWrapper, $installer, $sessionAudit, $newSessionBinding)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Desktop hook probe asset missing: $path"
}

$plugin = Get-Content -LiteralPath $pluginManifest -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal $plugin.name "antigravity-reliable-control" "Unexpected plugin name"
$hooks = Get-Content -LiteralPath $hooksManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$definition = $hooks.'antigravity-reliable-control-probe'
Assert-Equal $definition.enabled $true "Probe must be enabled after explicit installation"
Assert-Equal @($definition.PreToolUse).Count 1 "Probe must define one PreToolUse group"
Assert-Equal $definition.PreToolUse[0].matcher $coreMatcher "PreToolUse must cover the bounded core tool set"
Assert-True ([string]$definition.PreToolUse[0].hooks[0].command -match 'pre-tool-use\.cmd$') "Hook command must use the Windows wrapper"
Assert-Equal @($definition.PostToolUse).Count 1 "Probe must define one PostToolUse group"
Assert-Equal $definition.PostToolUse[0].matcher $coreMatcher "PostToolUse must cover the same bounded core tool set"
Assert-True ([string]$definition.PostToolUse[0].hooks[0].command -match 'post-tool-use\.cmd$') "PostToolUse must use the Windows wrapper"
$wrapperRaw = Get-Content -LiteralPath $hookWrapper -Raw -Encoding UTF8
Assert-True ($wrapperRaw -match 'powershell\.exe') "Windows hook wrapper does not launch PowerShell"
Assert-True ($wrapperRaw -match '%~dp0pre-tool-use\.ps1') "Windows hook wrapper is not plugin-relative"
$hookRaw = Get-Content -LiteralPath $hookScript -Raw -Encoding UTF8
Assert-True ($hookRaw -match 'antigravity-v351-binding-task-case-02') "Default fail-closed policy root is not the fresh v3.5.1 Canary"
Assert-True ($hookRaw -notmatch 'Join-Path \(\[IO\.Path\]::GetTempPath\(\)\) "antigravity-v35-binding-task-case-01"') "Default policy still protects the contaminated v3.5 case-01 root"
$postWrapperRaw = Get-Content -LiteralPath $postHookWrapper -Raw -Encoding UTF8
Assert-True ($postWrapperRaw -match '%~dp0post-tool-use\.ps1') "PostToolUse wrapper is not plugin-relative"

$tmp = Join-Path $env:TEMP ("antigravity-desktop-hook-probe-test-" + [guid]::NewGuid().ToString("N"))
$state = Join-Path $tmp "state"
$target = Join-Path $tmp "plugins\antigravity-reliable-control"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$sample = [ordered]@{
    conversationId = "11111111-2222-3333-4444-555555555555"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = "C:\private\brain"
    stepIdx = 7
    toolCall = [ordered]@{name="list_dir";args=[ordered]@{DirectoryPath="C:\private\workspace"}}
} | ConvertTo-Json -Depth 8 -Compress

$valid = Invoke-HookProcess -InputText $sample -StateRoot $state
Assert-Equal $valid.exit_code 0 "Valid hook probe invocation failed"
$validOutput = $valid.stdout.Trim() | ConvertFrom-Json
Assert-Equal $validOutput.decision "allow" "Probe must remain fail-open"
Assert-True (Test-Path -LiteralPath (Join-Path $state ".gemini-private") -PathType Leaf) "Probe state is not private-marked"
$event = Get-ChildItem -LiteralPath (Join-Path $state "events") -File -Filter "*.json" | Select-Object -First 1
Assert-True ($null -ne $event) "Probe did not write a bounded event"
$eventRaw = Get-Content -LiteralPath $event.FullName -Raw -Encoding UTF8
$eventValue = $eventRaw | ConvertFrom-Json
Assert-Equal $eventValue.schema "antigravity-desktop-hook-probe-event-v1" "Unexpected probe event schema"
Assert-Equal $eventValue.tool_name "list_dir" "Tool name missing from probe event"
Assert-Equal $eventValue.step_idx 7 "Step index missing from probe event"
Assert-Equal ([string]$eventValue.conversation_id_sha256).Length 64 "Conversation ID hash missing"
Assert-True ($eventRaw -notmatch [regex]::Escape("11111111-2222-3333-4444-555555555555")) "Probe leaked raw conversation ID"
Assert-True ($eventRaw -notmatch [regex]::Escape("C:\private\workspace")) "Probe leaked raw workspace path"
Assert-True ($eventRaw -notmatch "DirectoryPath") "Probe persisted raw tool arguments"

$malformed = Invoke-HookProcess -InputText "not-json" -StateRoot $state
Assert-Equal $malformed.exit_code 0 "Malformed hook input must not break the desktop loop"
$malformedOutput = $malformed.stdout.Trim() | ConvertFrom-Json
Assert-Equal $malformedOutput.decision "allow" "Malformed hook input must fail open during probe phase"

$normalCommandState = Join-Path $tmp "normal-command-state"
$normalArtifactRoot = Join-Path $normalCommandState "brain"
$normalStepRoot = Join-Path $normalArtifactRoot ".system_generated\steps\8"
New-Item -ItemType Directory -Force -Path $normalStepRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $normalStepRoot "output.txt"), "The command exited with code 0.`nOutput:`nPRIVATE_SUCCESS_OUTPUT`n", (New-Object Text.UTF8Encoding($false)))
$normalCommandSample = [ordered]@{
    conversationId = "22222222-3333-4444-5555-666666666666"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = $normalArtifactRoot
    stepIdx = 8
    toolCall = [ordered]@{name="run_command";args=[ordered]@{CommandLine="Write-Output safe";Cwd="C:\private\workspace";WaitMsBeforeAsync=1000}}
} | ConvertTo-Json -Depth 8 -Compress
$normalCommand = Invoke-HookProcess -InputText $normalCommandSample -StateRoot $normalCommandState
Assert-Equal $normalCommand.exit_code 0 "Normal run_command probe invocation failed (stderr=$($normalCommand.stderr.Trim()))"
Assert-Equal (($normalCommand.stdout.Trim() | ConvertFrom-Json).decision) "allow" "A normal run_command must remain allowed"
$normalPostSample = [ordered]@{
    conversationId = "22222222-3333-4444-5555-666666666666"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = $normalArtifactRoot
    stepIdx = 8
    error = ""
} | ConvertTo-Json -Depth 8 -Compress
$normalPost = Invoke-HookProcess -InputText $normalPostSample -StateRoot $normalCommandState -ScriptPath $postHookScript
Assert-Equal $normalPost.exit_code 0 "Successful PostToolUse invocation failed"
Assert-Equal $normalPost.stdout.Trim() "{}" "PostToolUse must return an empty JSON object"
$normalPostEvent = Get-ChildItem -LiteralPath (Join-Path $normalCommandState "correlations\post") -File -Filter "*.json" | Select-Object -First 1
Assert-True ($null -ne $normalPostEvent) "Successful PostToolUse did not write a completion record"
$normalPostValue = Get-Content -LiteralPath $normalPostEvent.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal $normalPostValue.correlation_status "matched" "PostToolUse did not match its PreToolUse record"
Assert-Equal $normalPostValue.outcome "succeeded" "Empty PostToolUse error must be succeeded"
Assert-Equal $normalPostValue.tool_name "run_command" "PostToolUse did not recover the tool name from PreToolUse"
Assert-Equal $normalPostValue.error_present $false "Successful PostToolUse incorrectly recorded an error"
Assert-Equal $normalPostValue.process_exit_code_observed 0 "Successful run_command exit code was not derived from host output"
Assert-Equal $normalPostValue.outcome_source "step-output-exit-code" "Successful run_command outcome source is incorrect"
Assert-Equal ([string]$normalPostValue.tool_result_sha256).Length 64 "Successful tool-result hash missing"
$normalPostRaw = Get-Content -LiteralPath $normalPostEvent.FullName -Raw -Encoding UTF8
Assert-True ($normalPostRaw -notmatch "PRIVATE_SUCCESS_OUTPUT") "PostToolUse persisted successful raw output"

$failedState = Join-Path $tmp "failed-command-state"
$failedArtifactRoot = Join-Path $failedState "brain"
$failedStepRoot = Join-Path $failedArtifactRoot ".system_generated\steps\10"
New-Item -ItemType Directory -Force -Path $failedStepRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $failedStepRoot "output.txt"), "The command exited with code 1.`nOutput:`nPRIVATE_PROCESS_OUTPUT`n", (New-Object Text.UTF8Encoding($false)))
$failedPreSample = [ordered]@{
    conversationId = "44444444-5555-6666-7777-888888888888"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = $failedArtifactRoot
    stepIdx = 10
    toolCall = [ordered]@{name="run_command";args=[ordered]@{CommandLine="exit 7";Cwd="C:\private\workspace";WaitMsBeforeAsync=1000}}
} | ConvertTo-Json -Depth 8 -Compress
$failedPre = Invoke-HookProcess -InputText $failedPreSample -StateRoot $failedState
Assert-Equal (($failedPre.stdout.Trim() | ConvertFrom-Json).decision) "allow" "Failed-command setup was not allowed"
$failedPostSample = [ordered]@{
    conversationId = "44444444-5555-6666-7777-888888888888"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = $failedArtifactRoot
    stepIdx = 10
    error = "exit status 7 PRIVATE_ERROR_TEXT"
} | ConvertTo-Json -Depth 8 -Compress
$failedPost = Invoke-HookProcess -InputText $failedPostSample -StateRoot $failedState -ScriptPath $postHookScript
Assert-Equal $failedPost.exit_code 0 "Failed PostToolUse invocation broke the hook loop"
Assert-Equal $failedPost.stdout.Trim() "{}" "Failed PostToolUse must still return an empty JSON object"
$failedPostEvent = Get-ChildItem -LiteralPath (Join-Path $failedState "correlations\post") -File -Filter "*.json" | Select-Object -First 1
$failedPostRaw = Get-Content -LiteralPath $failedPostEvent.FullName -Raw -Encoding UTF8
$failedPostValue = $failedPostRaw | ConvertFrom-Json
Assert-Equal $failedPostValue.correlation_status "matched" "Failed PostToolUse did not match its PreToolUse record"
Assert-Equal $failedPostValue.outcome "failed" "Non-empty PostToolUse error must be failed"
Assert-Equal ([string]$failedPostValue.error_sha256).Length 64 "Failed PostToolUse error hash missing"
Assert-True ($failedPostRaw -notmatch "PRIVATE_ERROR_TEXT") "PostToolUse persisted the raw error"
Assert-Equal $failedPostValue.process_exit_code_observed 1 "Failed run_command exit code was not derived from host output"
Assert-Equal $failedPostValue.outcome_source "step-output-exit-code" "Failed run_command outcome source is incorrect"
Assert-Equal ([string]$failedPostValue.tool_result_sha256).Length 64 "Failed tool-result hash missing"
Assert-True ($failedPostRaw -notmatch "PRIVATE_PROCESS_OUTPUT") "PostToolUse persisted failed raw output"

$orphanState = Join-Path $tmp "orphan-post-state"
$orphanPostSample = [ordered]@{
    conversationId = "55555555-6666-7777-8888-999999999999"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = "C:\private\brain"
    stepIdx = 11
    error = ""
} | ConvertTo-Json -Depth 8 -Compress
$orphanPost = Invoke-HookProcess -InputText $orphanPostSample -StateRoot $orphanState -ScriptPath $postHookScript
Assert-Equal $orphanPost.stdout.Trim() "{}" "Orphan PostToolUse must return an empty JSON object"
$orphanEvent = Get-ChildItem -LiteralPath (Join-Path $orphanState "correlations\post") -File -Filter "*.json" | Select-Object -First 1
$orphanValue = Get-Content -LiteralPath $orphanEvent.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal $orphanValue.correlation_status "orphan" "Missing PreToolUse must be explicit"

$malformedPost = Invoke-HookProcess -InputText "not-json" -StateRoot $orphanState -ScriptPath $postHookScript
Assert-Equal $malformedPost.exit_code 0 "Malformed PostToolUse input must not break the desktop loop"
Assert-Equal $malformedPost.stdout.Trim() "{}" "Malformed PostToolUse input must return an empty object"

$bindingTaskRoot = Join-Path $tmp "binding-task"
$bindingRegistryRoot = Join-Path $tmp "binding-registry"
$bindingStateRoot = Join-Path $tmp "desktop-bindings"
$bindingHookState = Join-Path $tmp "binding-hook-state"
New-Item -ItemType Directory -Force -Path $bindingTaskRoot | Out-Null
$governed = (& (Join-Path $ProjectRoot "src\scripts\new-governed-task.ps1") -ProjectRoot $bindingTaskRoot -RegistryRoot $bindingRegistryRoot -LogicalTaskId "binding-canary-task" -Objective "Write one bound Canary output" -AllowedPaths @("output.txt") -RequiredChecks @("binding-canary")) | ConvertFrom-Json
Assert-Equal $governed.status "success" "Binding fixture governed task creation failed"
$attempt = (& (Join-Path $ProjectRoot "src\scripts\new-attempt-record.ps1") -StateRoot (Join-Path $bindingTaskRoot "harness-state") -ProjectRoot $bindingTaskRoot -TaskId "binding-canary-task" -OperationId "bound-write" -AttemptId "binding-attempt-1") | ConvertFrom-Json
Assert-Equal $attempt.status "success" "Binding fixture Attempt creation failed"
$bindingConversation = "77777777-8888-9999-aaaa-bbbbbbbbbbbb"
$boundTarget = Join-Path $bindingTaskRoot "output.txt"
function New-BindingWritePayload([int]$Step) {
    [ordered]@{conversationId=$bindingConversation;workspacePaths=@($bindingTaskRoot);transcriptPath=(Join-Path $bindingTaskRoot "private-transcript.jsonl");artifactDirectoryPath=(Join-Path $bindingTaskRoot "private-artifacts");stepIdx=$Step;toolCall=[ordered]@{name="write_to_file";args=[ordered]@{TargetFile=$boundTarget;Overwrite=$false;CodeContent="PRIVATE_BOUND_CONTENT";Description="binding canary"}}} | ConvertTo-Json -Depth 10 -Compress
}
$unboundWrite = Invoke-HookProcess -InputText (New-BindingWritePayload 50) -StateRoot $bindingHookState -BindingStateRoot $bindingStateRoot -BindingPolicyRoot $bindingTaskRoot
$unboundOutput = $unboundWrite.stdout.Trim() | ConvertFrom-Json
Assert-Equal $unboundOutput.decision "deny" "A Canary-root write without a session binding must fail closed"
$unboundPre = Get-ChildItem -LiteralPath (Join-Path $bindingHookState "correlations\pre") -File | Select-Object -First 1
$unboundPreRaw = Get-Content -LiteralPath $unboundPre.FullName -Raw -Encoding UTF8
$unboundPreValue = $unboundPreRaw | ConvertFrom-Json
Assert-Equal $unboundPreValue.binding_status "missing" "Missing session binding status was not recorded"

$bindingResult = (& $newSessionBinding -StateRoot $bindingStateRoot -ConversationId $bindingConversation -TaskRoot $bindingTaskRoot -ContractPath $governed.contract -LedgerPath $attempt.path -AttemptId "binding-attempt-1" -Role "maker") | ConvertFrom-Json
Assert-Equal $bindingResult.status "success" "Valid desktop session binding was rejected"
Assert-True (Test-Path -LiteralPath (Join-Path $bindingStateRoot ".gemini-private") -PathType Leaf) "Desktop binding state is not private-marked"
$boundWrite = Invoke-HookProcess -InputText (New-BindingWritePayload 51) -StateRoot $bindingHookState -BindingStateRoot $bindingStateRoot -BindingPolicyRoot $bindingTaskRoot
$boundOutput = $boundWrite.stdout.Trim() | ConvertFrom-Json
Assert-Equal $boundOutput.decision "allow" "A valid active session binding should allow the bounded Canary write"
$boundHash = $bindingResult.conversation_id_sha256
$boundPreFile = Get-ChildItem -LiteralPath (Join-Path $bindingHookState "correlations\pre") -File | ForEach-Object { $value=Get-Content $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json; if($value.step_idx -eq 51){$_} } | Select-Object -First 1
$boundPreRaw = Get-Content -LiteralPath $boundPreFile.FullName -Raw -Encoding UTF8
$boundPreValue = $boundPreRaw | ConvertFrom-Json
Assert-Equal $boundPreValue.binding_status "active" "Active session binding status missing"
Assert-Equal ([string]$boundPreValue.bound_attempt_id_sha256).Length 64 "Bound Attempt hash missing"
Assert-True ($boundPreRaw -notmatch [regex]::Escape($bindingTaskRoot)) "Hook event leaked raw bound TaskRoot"
Assert-True ($boundPreRaw -notmatch "binding-attempt-1|binding-canary-task|PRIVATE_BOUND_CONTENT") "Hook event leaked raw binding or content"

New-Item -ItemType Directory -Force -Path (Join-Path $bindingTaskRoot "artifacts") | Out-Null
[IO.File]::WriteAllText((Join-Path $bindingTaskRoot "artifacts\binding-stop.json"), "{}`n", (New-Object Text.UTF8Encoding($false)))
$closed = (& (Join-Path $ProjectRoot "src\scripts\update-attempt-record.ps1") -LedgerPath $attempt.path -AttemptId "binding-attempt-1" -ExpectedVersion 1 -Status "stopped" -ExitCode 0 -EvidenceArtifact "artifacts/binding-stop.json") | ConvertFrom-Json
Assert-Equal $closed.status "success" "Binding fixture Attempt could not be stopped"
$staleWrite = Invoke-HookProcess -InputText (New-BindingWritePayload 52) -StateRoot $bindingHookState -BindingStateRoot $bindingStateRoot -BindingPolicyRoot $bindingTaskRoot
$staleOutput = $staleWrite.stdout.Trim() | ConvertFrom-Json
Assert-Equal $staleOutput.decision "deny" "A terminal bound Attempt must fail closed"
$stalePreFile = Get-ChildItem -LiteralPath (Join-Path $bindingHookState "correlations\pre") -File | ForEach-Object { $value=Get-Content $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json; if($value.step_idx -eq 52){$_} } | Select-Object -First 1
$stalePreValue = Get-Content -LiteralPath $stalePreFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal $stalePreValue.binding_status "attempt_not_running" "Terminal Attempt binding status is inaccurate"

$unrelatedRoot = Join-Path $tmp "unrelated"
New-Item -ItemType Directory -Force -Path $unrelatedRoot | Out-Null
$unrelatedPayload = [ordered]@{conversationId="88888888-9999-aaaa-bbbb-cccccccccccc";workspacePaths=@($unrelatedRoot);transcriptPath=(Join-Path $unrelatedRoot "t");artifactDirectoryPath=(Join-Path $unrelatedRoot "a");stepIdx=53;toolCall=[ordered]@{name="write_to_file";args=[ordered]@{TargetFile=(Join-Path $unrelatedRoot "unrelated.txt");Overwrite=$false;CodeContent="safe";Description="unrelated"}}} | ConvertTo-Json -Depth 10 -Compress
$unrelated = Invoke-HookProcess -InputText $unrelatedPayload -StateRoot $bindingHookState -BindingStateRoot $bindingStateRoot -BindingPolicyRoot $bindingTaskRoot
Assert-Equal (($unrelated.stdout.Trim() | ConvertFrom-Json).decision) "allow" "Writes outside the exact Canary policy root must remain observe-only"

$coreState = Join-Path $tmp "core-tool-state"
$coreConversation = "66666666-7777-8888-9999-aaaaaaaaaaaa"
$coreCases = @(
    [ordered]@{step=20;name="view_file";args=[ordered]@{AbsolutePath="C:\private\workspace\source.mp4";StartLine=1;EndLine=2}},
    [ordered]@{step=21;name="write_to_file";args=[ordered]@{TargetFile="C:\private\workspace\entry.md";Overwrite=$false;CodeContent="PRIVATE_CONTENT";Description="write"}},
    [ordered]@{step=22;name="replace_file_content";args=[ordered]@{TargetFile="C:\private\workspace\entry.md";Instruction="replace";TargetContent="PRIVATE_OLD";ReplacementContent="PRIVATE_NEW";StartLine=1;EndLine=1}},
    [ordered]@{step=23;name="multi_replace_file_content";args=[ordered]@{TargetFile="C:\private\workspace\entry.md";Instruction="multi";ReplacementChunks=@()}},
    [ordered]@{step=24;name="invoke_subagent";args=[ordered]@{Subagents=@([ordered]@{Role="parser";Prompt="PRIVATE_PROMPT";Workspace="C:\private\workspace"})}},
    [ordered]@{step=25;name="manage_subagents";args=[ordered]@{Action="list"}}
)
foreach($case in $coreCases) {
    $prePayload = [ordered]@{conversationId=$coreConversation;workspacePaths=@("C:\private\workspace");transcriptPath="C:\private\brain\transcript.jsonl";artifactDirectoryPath="C:\private\brain";stepIdx=$case.step;toolCall=[ordered]@{name=$case.name;args=$case.args}} | ConvertTo-Json -Depth 12 -Compress
    $preResult = Invoke-HookProcess -InputText $prePayload -StateRoot $coreState
    Assert-Equal (($preResult.stdout.Trim() | ConvertFrom-Json).decision) "allow" "Newly observed core tool must remain allow-only: $($case.name)"
    $postPayload = [ordered]@{conversationId=$coreConversation;workspacePaths=@("C:\private\workspace");transcriptPath="C:\private\brain\transcript.jsonl";artifactDirectoryPath="C:\private\brain";stepIdx=$case.step;error=""} | ConvertTo-Json -Depth 8 -Compress
    $postResult = Invoke-HookProcess -InputText $postPayload -StateRoot $coreState -ScriptPath $postHookScript
    Assert-Equal $postResult.stdout.Trim() "{}" "Core PostToolUse must return an empty object: $($case.name)"
}
$corePreFiles = @(Get-ChildItem -LiteralPath (Join-Path $coreState "correlations\pre") -File -Filter "*.json")
Assert-Equal $corePreFiles.Count $coreCases.Count "Every new core tool must create a Pre correlation record"
foreach($file in $corePreFiles) {
    $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    Assert-True ($raw -notmatch "PRIVATE_CONTENT|PRIVATE_PROMPT|PRIVATE_OLD|PRIVATE_NEW|C:\\private") "Core tool correlation leaked raw arguments or paths"
}
$fileToolRecords = @($corePreFiles | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.tool_name -in @("view_file","write_to_file","replace_file_content","multi_replace_file_content") })
foreach($record in $fileToolRecords) {
    Assert-True ([int]$record.target_path_count -ge 1) "File tool target path hash missing: $($record.tool_name)"
    Assert-Equal ([string]@($record.target_path_sha256)[0]).Length 64 "File tool target SHA-256 invalid: $($record.tool_name)"
}
$subagentRecord = @($corePreFiles | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.tool_name -eq "invoke_subagent" })[0]
Assert-Equal $subagentRecord.requested_subagent_count 1 "Subagent request count missing"

$auditResult = & $sessionAudit -StateRoot $coreState -ConversationId $coreConversation -ExpectedTools @($coreCases | ForEach-Object { $_.name }) | ConvertFrom-Json
Assert-Equal $auditResult.status "success" "Session hook audit failed"
Assert-Equal $auditResult.pre_count $coreCases.Count "Session audit Pre count mismatch"
Assert-Equal $auditResult.post_count $coreCases.Count "Session audit Post count mismatch"
Assert-Equal $auditResult.matched_count $coreCases.Count "Session audit matched count mismatch"
Assert-Equal $auditResult.missing_post_count 0 "Session audit reported missing Post events"
Assert-Equal $auditResult.orphan_post_count 0 "Session audit reported orphan Post events"
Assert-Equal @($auditResult.missing_expected_tools).Count 0 "Session audit missed expected core tools"

$sentinelState = Join-Path $tmp "sentinel-state"
$sentinelSample = [ordered]@{
    conversationId = "33333333-4444-5555-6666-777777777777"
    workspacePaths = @("C:\private\workspace")
    transcriptPath = "C:\private\brain\transcript.jsonl"
    artifactDirectoryPath = "C:\private\brain"
    stepIdx = 9
    toolCall = [ordered]@{name="run_command";args=[ordered]@{CommandLine="Write-Output blocked # ANTIGRAVITY_HOOK_DENY_SENTINEL_V1";Cwd="C:\private\workspace";WaitMsBeforeAsync=1000}}
} | ConvertTo-Json -Depth 8 -Compress
$sentinel = Invoke-HookProcess -InputText $sentinelSample -StateRoot $sentinelState
Assert-Equal $sentinel.exit_code 0 "Sentinel run_command hook invocation failed"
$sentinelOutput = $sentinel.stdout.Trim() | ConvertFrom-Json
Assert-Equal $sentinelOutput.decision "deny" "The exact sentinel command must be denied"
$sentinelEvent = Get-ChildItem -LiteralPath (Join-Path $sentinelState "events") -File -Filter "*.json" | Select-Object -First 1
$sentinelEventRaw = Get-Content -LiteralPath $sentinelEvent.FullName -Raw -Encoding UTF8
$sentinelEventValue = $sentinelEventRaw | ConvertFrom-Json
Assert-Equal $sentinelEventValue.decision "deny" "Sentinel deny decision missing from the event"
Assert-Equal $sentinelEventValue.reason_code "sentinel-deny" "Sentinel deny reason code missing"
Assert-True ($sentinelEventRaw -notmatch "ANTIGRAVITY_HOOK_DENY_SENTINEL_V1") "Probe log leaked the raw sentinel command"

$dryRun = & $installer -ProjectRoot $ProjectRoot -TargetRoot $target -DryRun | ConvertFrom-Json
Assert-Equal $dryRun.status "dry-run" "Desktop hook installer dry run failed"
Assert-True (-not (Test-Path -LiteralPath $target)) "Dry run modified the target"
$installed = & $installer -ProjectRoot $ProjectRoot -TargetRoot $target | ConvertFrom-Json
Assert-Equal $installed.status "installed" "Desktop hook plugin installation failed"
Assert-Equal $installed.hash_mismatches 0 "Installed desktop plugin hashes differ"
Assert-True (Test-Path -LiteralPath (Join-Path $target "hooks.json") -PathType Leaf) "Installed hooks.json missing"

[ordered]@{
    status = "success"
    summary = "Desktop Hooks provide privacy-bounded core observation, Pre/Post correlation, session auditing, exact-sentinel denial, and fail-closed Canary session/task/Attempt binding."
    cases = @("assets", "manifest", "list-dir-allow", "normal-command-allow", "sentinel-command-deny", "post-success", "post-failure", "post-orphan", "core-tool-coverage", "target-path-hashes", "subagent-count", "session-audit", "binding-missing-deny", "binding-active-allow", "binding-terminal-deny", "binding-privacy", "unrelated-write-allow", "malformed-input", "privacy", "dry-run", "install-hashes")
} | ConvertTo-Json -Compress
