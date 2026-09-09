# The validator implements the finite schema keyword subset used by this package.
# It is not a general JSON Schema engine and does not attest model identity.
function Assert-KnowledgeSingleLink([string]$Path) {
    # Windows file identity is package-local: no dependency on the global Hook.
    # Reject aliases conservatively, including a hardlinked output or original.
    if(-not ('KnowledgeGate.FileIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace KnowledgeGate {
    public static class FileIdentity {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileInfo {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            public uint VolumeSerial, SizeHigh, SizeLow, LinkCount, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);
        public static uint Links(string path) {
            using(var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
                FileInfo info;
                if(!GetFileInformationByHandle(file.SafeFileHandle, out info)) throw new IOException("file_identity_unavailable");
                return info.LinkCount;
            }
        }
    }
}
'@ | Out-Null
    }
    try {if([KnowledgeGate.FileIdentity]::Links($Path) -ne 1){throw 'hardlink_alias'}} catch {throw 'unsafe_path'}
}
function Test-KnowledgeSchema($Value, $Schema, [string]$At = '$') {
    $types=@($Schema.type); $typeOK=$false
    foreach($t in $types) {
        if(($t -eq 'null' -and $null -eq $Value) -or ($t -eq 'string' -and $Value -is [string]) -or ($t -eq 'boolean' -and $Value -is [bool]) -or ($t -eq 'number' -and ($Value -is [ValueType]) -and $Value -isnot [bool]) -or ($t -eq 'array' -and $Value -is [array]) -or ($t -eq 'object' -and $null -ne $Value -and $Value -is [pscustomobject])) {$typeOK=$true}
    }
    if(-not $typeOK){throw "Schema type at $At"}
    if($null -eq $Value){return}
    if($Schema.enum -and $Value -cnotin @($Schema.enum)){throw "Schema enum at $At"}
    if($Value -is [string]) {
        if($Schema.minLength -and $Value.Length -lt $Schema.minLength){throw "Schema length at $At"}
        if($Schema.pattern -and $Value -cnotmatch $Schema.pattern){throw "Schema pattern at $At"}
    }
    if($types -contains 'number' -and $null -ne $Schema.minimum -and $Value -lt $Schema.minimum){throw "Schema minimum at $At"}
    if($Value -is [array]) {
        if($Schema.minItems -and $Value.Count -lt $Schema.minItems){throw "Schema items at $At"}
        foreach($item in $Value){Test-KnowledgeSchema $item $Schema.items "$At[]"}
    }
    if($types -contains 'object') {
        $names=@($Value.PSObject.Properties.Name)
        foreach($required in @($Schema.required)){if($required -cnotin $names){throw "Schema required at $At"}}
        foreach($name in $names){
            if($name -cnotin @($Schema.properties.PSObject.Properties.Name)){throw "Schema unknown field at $At"}
            Test-KnowledgeSchema $Value.$name $Schema.properties.$name "$At.$name"
        }
    }
}
function Resolve-KnowledgePath([string]$Root,[string]$Relative,[switch]$AllowMissing) {
    if([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?"<>|]' -or $Relative -match '(^|[\\/])\.{1,2}([\\/]|$)' -or $Relative -match '(^|[\\/])[^\\/]*[. ]([\\/]|$)'){throw 'unsafe_path'}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $target=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(-not $target.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'unsafe_path'}
    $cursor=$base
    $rootItem=Get-Item -LiteralPath $base -Force
    while($null -ne $rootItem){if($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'unsafe_path'};$rootItem=$rootItem.Parent}
    foreach($part in ($Relative -split '[\\/]')) {
        $cursor=Join-Path $cursor $part
        if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'unsafe_path'}}
        elseif(-not $AllowMissing){throw 'missing_path'}
    }
    if(Test-Path -LiteralPath $target -PathType Leaf){Assert-KnowledgeSingleLink $target}
    return $target
}
function Get-KnowledgeHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Test-KnowledgeRetiredText([string]$Text,$Claims) {
    foreach($claim in @($Claims)) {
        $retired=@($claim.previous_text)
        if($claim.status -eq 'rejected'){$retired+=@($claim.text)}
        foreach($old in $retired){if(-not [string]::IsNullOrEmpty($old) -and $Text.Contains([string]$old)){return $true}}
    }
    return $false
}
function Get-KnowledgeSurfaceText($Final,$Claims,$Surface) {
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($section in @($Final.required_sections)) {
        $lines.Add('## '+$section)
        if($section -ceq $Final.required_sections[0]) {
            foreach($id in @($Surface.claim_ids)) {
                $claim=@($Claims|Where-Object {$_.id -ceq $id})
                if($claim.Count -ne 1){throw 'invalid_final_claim'}
                $lines.Add('<!-- claim:'+$id+' -->')
                $prefix=if($claim[0].source_fidelity -eq 'uncertain' -or $claim[0].external_truth -eq 'uncertain' -or $claim[0].status -eq 'downgraded'){'[Uncertain] '}else{''}
                $lines.Add($prefix+[string]$claim[0].text)
            }
        }
        $lines.Add('')
    }
    foreach($link in @($Final.wiki_links)){$lines.Add('[['+$link+']]')}
    foreach($attachment in @($Final.attachments)){$lines.Add('![['+$attachment+']]')}
    $text=($lines -join "`n")+"`n"
    if(Test-KnowledgeRetiredText $text $Claims){throw 'stale_claim_wording'}
    return $text
}
