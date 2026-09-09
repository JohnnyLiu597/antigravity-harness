param([string]$ProjectRoot = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$sync = Join-Path $ProjectRoot 'deploy\sync-to-runtime.ps1'
$import = Join-Path $ProjectRoot 'deploy\sync-from-runtime.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('antigravity-modern-skills-' + [guid]::NewGuid().ToString('N'))
function Put($Path,$Value) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null; [IO.File]::WriteAllText($Path,$Value,(New-Object Text.UTF8Encoding($false))) }
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action) { $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }; Assert $failed 'Expected refusal.' }
$source = Join-Path $fixture 'project'
$runtime = Join-Path $fixture 'runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
Put (Join-Path $source 'src\skills\example\SKILL.md') 'new skill'
Put (Join-Path $source 'src\skills\example\references\guide.md') 'new guide'
Put (Join-Path $source 'src\config\private.json') '{"private":true}'
Put (Join-Path $runtime 'skills\example\SKILL.md') 'old legacy'
Put (Join-Path $runtime 'config\skills\example\SKILL.md') 'old modern'
Put (Join-Path $runtime 'config\private.json') '{"untouched":true}'
$installed = & $sync -ProjectRoot $source -GeminiHome $runtime | ConvertFrom-Json
Assert ((Get-Content -LiteralPath (Join-Path $runtime 'config\skills\example\SKILL.md') -Raw) -eq 'new skill') 'Canonical Skills path was not installed.'
Assert ((Get-Content -LiteralPath (Join-Path $runtime 'skills\example\SKILL.md') -Raw) -eq 'new skill') 'Legacy Skills path was not retained.'
Assert ((Get-Content -LiteralPath (Join-Path $runtime 'config\private.json') -Raw) -eq '{"untouched":true}') 'Installing canonical skills broadened config access.'
$tx = Get-Content -LiteralPath $installed.transaction_manifest -Raw | ConvertFrom-Json
Assert (@($tx.files | Where-Object { $_.relative_path -match '^config[\\/]skills[\\/]' }).Count -eq 2) 'Both canonical files are absent from the existing rollback transaction.'
& $sync -GeminiHome $runtime -RollbackManifest $installed.transaction_manifest | Out-Null
Assert ((Get-Content -LiteralPath (Join-Path $runtime 'skills\example\SKILL.md') -Raw) -eq 'old legacy') 'Rollback did not restore legacy skill.'
Assert ((Get-Content -LiteralPath (Join-Path $runtime 'config\skills\example\SKILL.md') -Raw) -eq 'old modern') 'Rollback did not restore canonical skill.'

$privateRuntime = Join-Path $fixture 'private-runtime'
Put (Join-Path $privateRuntime 'config\skills\example\.gemini-private') ''
Put (Join-Path $privateRuntime 'config\skills\example\SKILL.md') 'private modern'
& $sync -ProjectRoot $source -GeminiHome $privateRuntime | Out-Null
Assert (-not (Test-Path -LiteralPath (Join-Path $privateRuntime 'skills\example\SKILL.md'))) 'Canonical private marker did not protect both copies.'
Put (Join-Path $privateRuntime 'skills\legacy-private\.gemini-private') ''
Put (Join-Path $source 'src\skills\legacy-private\SKILL.md') 'do not install'
& $sync -ProjectRoot $source -GeminiHome $privateRuntime | Out-Null
Assert (-not (Test-Path -LiteralPath (Join-Path $privateRuntime 'config\skills\legacy-private\SKILL.md'))) 'Legacy private marker did not protect canonical copy.'

$importRuntime=Join-Path $fixture 'import-runtime'; $importProject=Join-Path $fixture 'import-project'
New-Item -ItemType Directory -Force -Path $importProject | Out-Null
Put (Join-Path $importRuntime 'config\skills\canonical-only\SKILL.md') 'canonical'
Put (Join-Path $importRuntime 'skills\legacy-only\SKILL.md') 'legacy'
Put (Join-Path $importRuntime 'config\skills\same\SKILL.md') 'same'
Put (Join-Path $importRuntime 'skills\same\SKILL.md') 'same'
Put (Join-Path $importRuntime 'config\skills\private\SKILL.md') 'must not import'
Put (Join-Path $importRuntime 'skills\private\.gemini-private') ''
& $import -ProjectRoot $importProject -GeminiHome $importRuntime | Out-Null
Assert (Test-Path -LiteralPath (Join-Path $importProject 'src\skills\canonical-only\SKILL.md')) 'Canonical-only skill was not imported.'
Assert (Test-Path -LiteralPath (Join-Path $importProject 'src\skills\legacy-only\SKILL.md')) 'Legacy fallback was not imported.'
Assert (-not (Test-Path -LiteralPath (Join-Path $importProject 'src\skills\private'))) 'Private counterpart was imported.'
Put (Join-Path $importRuntime 'skills\same\SKILL.md') 'drift'
Put (Join-Path $importProject 'src\preserve.txt') 'preserve on conflict'
Reject { & $import -ProjectRoot $importProject -GeminiHome $importRuntime -Refresh }
Assert (Test-Path -LiteralPath (Join-Path $importProject 'src\preserve.txt')) 'Conflict was detected after destructive Refresh.'
[ordered]@{ status='passed'; cases=12; fixture=$fixture; summary='Modern+legacy skill transactions and conservative import passed.' } | ConvertTo-Json -Compress
