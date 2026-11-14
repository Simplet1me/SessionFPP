param([string]$GamePath)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Closed
$root=Resolve-Game $GamePath -ForUninstall
# Prefer the recorded mod location even if UE4SS has since been removed/moved.
$locations=@('Mods','ue4ss\Mods')|Where-Object {Test-Path -LiteralPath (Safe-Path $root ($_+'\SessionFPP\.install-state.json'))}
if(@($locations).Count -eq 0){Write-Output 'No ownership record found. Nothing removed; this may be a manual/older installation.';exit 0}
if(@($locations).Count -ne 1){throw 'Multiple ownership records found. Nothing removed.'}
$relative=@($locations)[0]
$context=@{Root=$root;ModsRelative=$relative;Mods=(Safe-Path $root $relative)}
$modRelative=$relative+'\'+$script:ModName
$modDir=Safe-Path $root $modRelative
$statePath=Safe-Path $root ($modRelative+'\.install-state.json')
$state=Read-State $statePath $root
foreach($file in $state.ModFiles){
    if($file.Path -notin @('dlls\main.dll','enabled.txt') -or $file.Sha256 -notmatch '^[0-9A-Fa-f]{64}$'){throw 'Unsafe mod ownership record.'}
    [void](Safe-Path $root ($modRelative+'\'+$file.Path))
}
# Preflight all paths before changing any files.
$list=Safe-Path $root ($relative+'\mods.txt')
$text=Read-Text $list
$newText=Set-ModRow $text $false
$otherMods=@(Get-OtherMods $context)
$removeRuntime=[bool]$state.RuntimeInstalledByUs -and $otherMods.Count -eq 0
if($removeRuntime){
    foreach($file in $state.RuntimeFiles){
        $path=Safe-Path $root $file.Path
        if((Test-Path -LiteralPath $path) -and (Hash $path) -ne $file.Sha256){$removeRuntime=$false}
    }
}
foreach($file in $state.ModFiles){
    $path=Safe-Path $root ($modRelative+'\'+$file.Path)
    if(Test-Path -LiteralPath $path){
        if($file.Path -eq 'enabled.txt' -or (Hash $path) -eq $file.Sha256){Remove-Item -LiteralPath $path -Force}
        else{Write-Warning "Modified file preserved: $path"}
    }
}
if(Test-Path -LiteralPath $list){
    if([bool]$state.ModsListCreated -and [string]::IsNullOrWhiteSpace($newText)){Remove-Item -LiteralPath $list -Force}
    else{Write-Text $list $newText}
}
if($removeRuntime){
    foreach($file in $state.RuntimeFiles){$path=Safe-Path $root $file.Path;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
    Write-Output 'Removed the unchanged UE4SS dependencies installed by this package.'
} elseif([bool]$state.RuntimeInstalledByUs){
    Write-Output 'UE4SS kept: other mods/loader files exist, or dependency files were modified.'
} else {Write-Output 'Pre-existing UE4SS kept.'}
Remove-Item -LiteralPath $statePath -Force
Remove-Empty (Safe-Path $root ($modRelative+'\dlls'));Remove-Empty $modDir
if([bool]$state.ModsDirectoryCreated){Remove-Empty $context.Mods}
Write-Output 'SessionFPP uninstalled. Other mods, settings, logs and saves were preserved.'
