param([Parameter(Mandatory=$true)][string]$ProjectRoot,[ValidateSet('observe','guarded','strict')][string]$Mode='observe',[string]$PolicyPath='')
. (Join-Path $PSScriptRoot 'resolve-desktop-control-library.ps1')
try {
 if($Mode -eq 'strict'){@{status='unavailable';reason='independent_os_execution_boundary_not_established';mode='strict'}|ConvertTo-Json -Compress;return}
 $root=Get-AgPath $ProjectRoot
 if(-not(Test-Path -LiteralPath $root -PathType Container) -or $root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\')){throw 'project_root_invalid'}
 if(-not $PolicyPath){$PolicyPath=(Get-AgRoots).policy}
 $result=Invoke-AgLock ($PolicyPath+'.lock') {
  $p=if(Test-Path -LiteralPath $PolicyPath){Read-AgJson $PolicyPath}else{[pscustomobject]@{schema='antigravity-desktop-project-policy-v1';revision=0;projects=@()}}
  if($p.schema -ne 'antigravity-desktop-project-policy-v1'){throw 'policy_schema'}
  foreach($existing in @($p.projects)){if($existing.project_root -ne $root -and ((Test-AgWithin $root $existing.project_root) -or (Test-AgWithin $existing.project_root $root))){throw 'overlapping_registration'}}
  $p.projects=@($p.projects|Where-Object {$_.project_root -ne $root})+@(@{project_id=(Get-AgHash $root.ToLowerInvariant());project_root=$root;mode=$Mode;authority='operator-unattested';registered_at=[DateTime]::UtcNow.ToString('o')})
  $p.revision=[int]$p.revision+1;Write-AgAtomic $PolicyPath $p
  $marker=Join-Path (Split-Path -Parent $PolicyPath) '.gemini-private';if(-not(Test-Path -LiteralPath $marker)){[IO.File]::WriteAllText($marker,'')}
  return @{status='success';mode=$Mode;revision=$p.revision;policy=$PolicyPath;strict='unavailable';boundary='same-user-bypassable'}
 };$result|ConvertTo-Json -Compress
}catch{@{status='error';reason='project_registration_rejected'}|ConvertTo-Json -Compress}
