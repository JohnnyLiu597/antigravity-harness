Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
try {
 . (Join-Path $PSScriptRoot 'control-lib.ps1')
 $inputValue=Read-AgHookInput
 $null=Add-AgOperation -InputValue $inputValue -Phase Post
}catch {
 # Missing Post evidence stays unresolved; never persist raw error or transcript.
 [Console]::Error.WriteLine('antigravity_post_evidence_unavailable')
}
[Console]::Out.WriteLine('{}')
