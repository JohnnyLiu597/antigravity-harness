# Source and installed Antigravity runtime share the existing plugin implementation.
$candidates=@((Join-Path $PSScriptRoot '..\desktop-hooks\antigravity-reliable-control\hooks\control-lib.ps1'),(Join-Path $PSScriptRoot '..\config\plugins\antigravity-reliable-control\hooks\control-lib.ps1'))
$library=@($candidates|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1)
if($library.Count -ne 1){throw 'Antigravity Desktop control library is not installed.'}
. $library[0]
