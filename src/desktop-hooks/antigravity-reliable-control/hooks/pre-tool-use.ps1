Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Default deny survives input, policy, and logging failures.
$decision='deny';$reason='invalid_hook_input'
try {
 . (Join-Path $PSScriptRoot 'control-lib.ps1')
 $inputValue=Read-AgHookInput
 $authorization=Get-AgAuthorization $inputValue
 $decision=$authorization.decision;$reason=$authorization.reason_code
 try {
  $operation=Add-AgOperation -InputValue $inputValue -Phase Pre -Authorization $authorization
  if($operation.admission -eq 'deny'){$decision='deny';$reason='operation_replay_or_denied'}
 }catch {
  $tool=[string](Get-AgField (Get-AgField $inputValue 'toolCall') 'name' '')
  if($authorization.mode -ne 'observe' -or $decision -eq 'deny' -or $tool -in @('write_to_file','replace_file_content','multi_replace_file_content','run_command','invoke_subagent','manage_subagents')){$decision='deny';$reason='admission_or_journal_unavailable'}
 }
}catch { $decision='deny';$reason='hook_input_or_policy_unavailable' }
[Console]::Out.WriteLine((@{decision=$decision;reason=$reason}|ConvertTo-Json -Compress))
