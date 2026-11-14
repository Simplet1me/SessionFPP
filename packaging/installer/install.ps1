param([string]$GamePath)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Closed
$root=Resolve-Game $GamePath
$context=Get-Context $root
$payload=Join-Path $PSScriptRoot 'payload'
if(-not (Test-Path -LiteralPath (Join-Path $payload 'manifest.json'))){
    # Repository entry points are templates, without a duplicate runtime payload.
    # Resolve the newest built release when invoked directly from this folder.
    $repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $release=$null
    if(Test-Path -LiteralPath (Join-Path $repository 'CMakeLists.txt')){
        $built=@(foreach($folder in @('release','dist')){
            $releaseRoot=Join-Path $repository $folder
            if(Test-Path -LiteralPath $releaseRoot){Get-ChildItem -LiteralPath $releaseRoot -Directory}
        })
        $release=$built |
            Where-Object {$_.Name -match '^(?:SessionFPP-)?\d+\.\d+\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'payload\manifest.json'))} |
            Sort-Object {[version]($_.Name -replace '^SessionFPP-','')} -Descending | Select-Object -First 1
    }
    if(-not $release){throw 'Installer payload is missing. Extract the entire release ZIP and run Install.cmd beside the payload folder, or build a release first.'}
    $payload=Join-Path $release.FullName 'payload'
    Write-Output "Using built release payload: $payload"
}
try {$manifest=(Read-Text (Join-Path $payload 'manifest.json'))|ConvertFrom-Json}
catch {throw 'Package manifest is not valid JSON. Extract a fresh copy of the complete release ZIP.'}
if($null -eq $manifest -or $null -eq $manifest.PSObject.Properties['Files'] -or $null -eq $manifest.PSObject.Properties['Version']){
    throw 'Package manifest is missing Files or Version. Extract a fresh copy of the complete release ZIP.'
}
$allowed=@('mod\dlls\main.dll','mod\enabled.txt','ue4ss\UE4SS.dll','ue4ss\dwmapi.dll','ue4ss\UE4SS-settings.ini')
if(@($manifest.Files).Count -ne $allowed.Count){throw 'Incomplete package manifest.'}
foreach($file in $manifest.Files){
    if($null -eq $file -or $null -eq $file.PSObject.Properties['Path'] -or $null -eq $file.PSObject.Properties['Sha256']){throw 'Invalid payload entry in package manifest.'}
    if($file.Path -notin $allowed){throw 'Unexpected package payload.'}
    if((Hash (Safe-Path $payload $file.Path)) -ne $file.Sha256){throw "Package checksum mismatch: $($file.Path)"}
}
if(@($manifest.Files.Path|Sort-Object -Unique).Count -ne $allowed.Count){throw 'Duplicate payload entries.'}
$modRelative=$context.ModsRelative+'\'+$script:ModName
$modDir=Safe-Path $root $modRelative
$statePath=Safe-Path $root ($modRelative+'\.install-state.json')
$oldState=Read-State $statePath $root
$runtimeFiles=@()
$owned=$false
if($oldState){$owned=[bool]$oldState.RuntimeInstalledByUs;$runtimeFiles=@($oldState.RuntimeFiles)}
if(-not $context.ExistingRuntime){
    foreach($name in @('dwmapi.dll','UE4SS-settings.ini')){
        if(Test-Path -LiteralPath (Safe-Path $root $name)){throw "Existing $name detected without UE4SS.dll. No file was overwritten; repair the existing loader first."}
    }
    $owned=$true
    $runtimeFiles=@($manifest.Files|Where-Object {$_.Path.StartsWith('ue4ss\')}|ForEach-Object {@{Path=$_.Path.Substring(6);Sha256=$_.Sha256}})
} else {
    $runtimeDll=Safe-Path $root $(if($context.RuntimeRelative){$context.RuntimeRelative+'\UE4SS.dll'}else{'UE4SS.dll'})
    $known=($manifest.Files|Where-Object Path -eq 'ue4ss\UE4SS.dll').Sha256
    if((Hash $runtimeDll) -ne $known){Write-Warning 'Existing UE4SS differs from the tested 3.0.1 build. It will be preserved. This mod requires the UE4SS 3.0.1 C++ ABI.'}
    Write-Output 'Existing UE4SS detected: dependency files and settings will not be overwritten.'
}
$list=Safe-Path $root ($context.ModsRelative+'\mods.txt')
$oldText=Read-Text $list
$newText=Set-ModRow $oldText $true
$modsCreated=-not (Test-Path -LiteralPath $context.Mods)
$listCreated=-not (Test-Path -LiteralPath $list)
if($oldState){$modsCreated=[bool]$oldState.ModsDirectoryCreated;$listCreated=[bool]$oldState.ModsListCreated}
$state=@{Schema=1;Mod=$script:ModName;Version=$manifest.Version;GameRoot=$root;RuntimeInstalledByUs=$owned;RuntimeFiles=$runtimeFiles;ModsDirectoryCreated=$modsCreated;ModsListCreated=$listCreated;ModFiles=@($manifest.Files|Where-Object {$_.Path.StartsWith('mod\')}|ForEach-Object {@{Path=$_.Path.Substring(4);Sha256=$_.Sha256}})}
$changes=[Collections.Generic.List[object]]::new()
function Save-And-Copy([string]$Destination,[string]$Source) {
    $before=$null; if(Test-Path -LiteralPath $Destination){$before=[IO.File]::ReadAllBytes($Destination)}
    $changes.Add(@{Path=$Destination;Before=$before})
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Destination)) -Force | Out-Null
    [IO.File]::WriteAllBytes($Destination,[IO.File]::ReadAllBytes($Source))
}
try {
    New-Item -ItemType Directory -Path $modDir -Force | Out-Null
    # Write-ahead ownership journal: a power interruption still leaves an uninstall record.
    $before=$null; if(Test-Path -LiteralPath $statePath){$before=[IO.File]::ReadAllBytes($statePath)}
    $changes.Add(@{Path=$statePath;Before=$before})
    Write-Text $statePath ($state|ConvertTo-Json -Depth 6)
    if(-not $context.ExistingRuntime){
        foreach($file in $runtimeFiles){Save-And-Copy (Safe-Path $root $file.Path) (Safe-Path $payload ('ue4ss\'+$file.Path))}
    }
    foreach($file in $state.ModFiles){Save-And-Copy (Safe-Path $root ($modRelative+'\'+$file.Path)) (Safe-Path $payload ('mod\'+$file.Path))}
    $before=$null; if(Test-Path -LiteralPath $list){$before=[IO.File]::ReadAllBytes($list)}
    $changes.Add(@{Path=$list;Before=$before})
    Write-Text $list $newText
    foreach($file in $state.ModFiles){if((Hash (Safe-Path $root ($modRelative+'\'+$file.Path))) -ne $file.Sha256){throw 'Installed mod verification failed.'}}
} catch {
    for($i=$changes.Count-1;$i -ge 0;$i--){
        $change=$changes[$i]
        if($null -eq $change.Before){if(Test-Path -LiteralPath $change.Path){Remove-Item -LiteralPath $change.Path -Force}}
        else{[IO.File]::WriteAllBytes($change.Path,$change.Before)}
    }
    Remove-Empty (Safe-Path $root ($modRelative+'\dlls'));Remove-Empty $modDir
    if($modsCreated){Remove-Empty $context.Mods}
    throw
}
Write-Output "Installed SessionFPP $($manifest.Version) to $modDir"
Write-Output 'G / controller RB: toggle first/third person.'
if($owned){Write-Output 'UE4SS ownership recorded. Uninstall removes it only if no other mods use it and its files are unchanged.'}
