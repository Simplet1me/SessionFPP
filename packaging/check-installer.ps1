$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..\artifacts\installer-check'
$root=[IO.Path]::GetFullPath($root)
New-Item -ItemType Directory -Force $root | Out-Null
$package=Join-Path $PSScriptRoot '..\release\0.3.1'
function Assert($ok,$message){if(-not $ok){throw $message}}
foreach($case in @('fresh','shared','nested')){
    $game=Join-Path $root $case
    New-Item -ItemType Directory -Force $game | Out-Null
    [IO.File]::WriteAllText((Join-Path $game 'SessionGame-Win64-Shipping.exe'),'fixture')
    $runtime=if($case -eq 'nested'){Join-Path $game 'ue4ss'}else{$game}
    if($case -ne 'fresh'){
        New-Item -ItemType Directory -Force (Join-Path $runtime 'Mods\OtherMod') | Out-Null
        [IO.File]::WriteAllText((Join-Path $runtime 'UE4SS.dll'),'existing-runtime')
        [IO.File]::WriteAllText((Join-Path $runtime 'Mods\mods.txt'),"OtherMod : 1`r`n")
    }
    $mods=Join-Path $runtime 'Mods'
    & (Join-Path $package 'install.ps1') -GamePath $game
    & (Join-Path $package 'install.ps1') -GamePath $game
    Assert (Test-Path (Join-Path $mods 'SessionFPP\dlls\main.dll')) 'DLL missing'
    $rows=[IO.File]::ReadAllText((Join-Path $mods 'mods.txt'))
    Assert (([regex]::Matches($rows,'SessionFPP : 1')).Count -eq 1) 'Duplicate mod row'
    & (Join-Path $package 'uninstall.ps1') -GamePath $game
    Assert (-not (Test-Path (Join-Path $mods 'SessionFPP\dlls\main.dll'))) 'DLL not removed'
    if($case -eq 'fresh'){Assert (-not (Test-Path (Join-Path $game 'UE4SS.dll'))) 'Owned loader retained unexpectedly'}
    else {
        Assert (([IO.File]::ReadAllText((Join-Path $runtime 'UE4SS.dll'))) -eq 'existing-runtime') 'Existing loader changed'
        Assert (([IO.File]::ReadAllText((Join-Path $mods 'mods.txt'))) -eq "OtherMod : 1`r`n") 'Other mod list changed'
    }
}
Write-Output 'PASS: fresh/shared/nested layouts, reinstall, uninstall, loader and other-mod preservation.'
