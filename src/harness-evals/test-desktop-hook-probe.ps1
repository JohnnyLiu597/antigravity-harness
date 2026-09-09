param([string]$ProjectRoot='')
if(-not $ProjectRoot){$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\\..'))}
# v3.5.1 source is retained in tests/fixtures/v351; semantics intentionally migrated.
& (Join-Path $PSScriptRoot 'test-v4-events.ps1') -ProjectRoot $ProjectRoot
