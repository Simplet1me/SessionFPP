Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:ModName='SessionFPP'
$script:Utf8=[System.Text.UTF8Encoding]::new($false,$true)

function Assert-Closed {
    if(Get-Process -Name 'SessionGame-Win64-Shipping' -ErrorAction SilentlyContinue){throw 'Please close Session before installing or uninstalling.'}
}
function Find-GameFolder([string]$GamePath) {
    if([string]::IsNullOrWhiteSpace($GamePath)){return $null}
    $GamePath=$GamePath.Trim().Trim('"')
    if(-not (Test-Path -LiteralPath $GamePath)){return $null}
    $item=Get-Item -LiteralPath $GamePath
    if(-not $item.PSIsContainer){$GamePath=$item.DirectoryName}
    foreach($candidate in @($GamePath,(Join-Path $GamePath 'SessionGame\Binaries\Win64'),(Join-Path $GamePath 'Binaries\Win64'))){
        if(Test-Path -LiteralPath (Join-Path $candidate 'SessionGame-Win64-Shipping.exe') -PathType Leaf){
            $root=[IO.Path]::GetFullPath($candidate).TrimEnd('\')
            Assert-NoReparse $root
            return $root
        }
    }
    return $null
}
function Get-SteamDriveRoots {
    # Bounded discovery only: never recursively walk disks or network shares.
    foreach($drive in [IO.DriveInfo]::GetDrives()){
        if($drive.IsReady -and $drive.DriveType -in @([IO.DriveType]::Fixed,[IO.DriveType]::Removable)){$drive.RootDirectory.FullName}
    }
}
function Get-SteamInstallRoots {
    foreach($entry in @(
        @('HKCU:\Software\Valve\Steam','SteamPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam','InstallPath')
    )){
        $value=Get-ItemProperty -LiteralPath $entry[0] -ErrorAction SilentlyContinue
        if($value -and $value.PSObject.Properties[$entry[1]]){$value.PSObject.Properties[$entry[1]].Value}
    }
    foreach($name in @('ProgramFiles(x86)','ProgramFiles')){
        $folder=[Environment]::GetEnvironmentVariable($name)
        if($folder){Join-Path $folder 'Steam'}
    }
}
function Read-SteamLibraryPaths([string]$File) {
    if(-not (Test-Path -LiteralPath $File -PathType Leaf)){return}
    # Modern "path" fields and old numbered string entries; unescape VDF paths.
    foreach($line in [IO.File]::ReadAllLines($File)){
        if($line -match '^\s*"(?:path|\d+)"\s*"((?:\\.|[^"\\])*)"\s*$'){
            $path=$Matches[1].Replace('\\','\').Replace('\"','"')
            if([IO.Path]::IsPathRooted($path)){$path}
        }
    }
}
function Find-SteamGames {
    $libraries=[Collections.Generic.List[string]]::new()
    $seenLibraries=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $games=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $driveRoots=@(Get-SteamDriveRoots)
    # First pass: each disk's conventional SteamLibrary, then Steam's own roots.
    foreach($drive in $driveRoots){$libraries.Add((Join-Path $drive 'SteamLibrary'))}
    foreach($path in @(Get-SteamInstallRoots)){
        if(-not [string]::IsNullOrWhiteSpace($path)){$libraries.Add($path)}
    }
    foreach($drive in $driveRoots){$libraries.Add((Join-Path $drive 'Steam'))}
    # Follow registered libraryfolders.vdf paths, including custom folder names.
    # The list may grow while visiting it; a set prevents cycles/duplicates.
    for($index=0;$index -lt $libraries.Count -and $index -lt 256;$index++){
        $library=$libraries[$index]
        try {
            $library=[IO.Path]::GetFullPath($library).TrimEnd('\')
            if(-not $seenLibraries.Add($library) -or -not (Test-Path -LiteralPath $library -PathType Container)){continue}
            foreach($vdf in @('steamapps\libraryfolders.vdf','config\libraryfolders.vdf')){
                foreach($path in @(Read-SteamLibraryPaths (Join-Path $library $vdf))){$libraries.Add($path)}
            }
            $steamapps=Join-Path $library 'steamapps'
            $folders=[Collections.Generic.List[string]]::new()
            $manifest=Join-Path $steamapps 'appmanifest_861650.acf'
            if(Test-Path -LiteralPath $manifest -PathType Leaf){
                $acf=[IO.File]::ReadAllText($manifest)
                if($acf -match '(?m)^\s*"installdir"\s*"([^"\\/]+)"\s*$'){
                    $folder=$Matches[1]
                    if($folder -notin @('.','..')){$folders.Add((Join-Path $steamapps ('common\'+$folder)))}
                }
            }
            $folders.Add((Join-Path $steamapps 'common\Session'))
            foreach($folder in $folders){
                $resolved=Find-GameFolder $folder
                if($resolved -and $games.Add($resolved)){$resolved}
            }
        } catch {Write-Warning "Skipped Steam library '$library': $($_.Exception.Message)"}
    }
}
function Resolve-Game([string]$GamePath,[switch]$ForUninstall) {
    if([string]::IsNullOrWhiteSpace($GamePath)){
        Write-Host 'Looking for Session in SteamLibrary folders and registered Steam libraries...'
        $games=@(Find-SteamGames)
        if($ForUninstall){
            $installed=@($games|Where-Object {
                (Test-Path -LiteralPath (Join-Path $_ 'Mods\SessionFPP\.install-state.json')) -or
                (Test-Path -LiteralPath (Join-Path $_ 'ue4ss\Mods\SessionFPP\.install-state.json'))
            })
            if($installed.Count){$games=$installed}
        }
        if($games.Count -eq 1){Write-Host "Detected Session: $($games[0])";return $games[0]}
        if($games.Count -gt 1){
            Write-Host 'Multiple Session installations found:'
            for($i=0;$i -lt $games.Count;$i++){Write-Host (('{0}. {1}' -f ($i+1),$games[$i]))}
            $choice=Read-Host 'Select an installation number'
            $number=0
            if(-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $games.Count){throw 'Invalid installation selection. Nothing changed.'}
            return $games[$number-1]
        }
        $GamePath=Read-Host 'Session was not found automatically. Enter the game folder or game EXE path'
    }
    $resolved=Find-GameFolder $GamePath
    if($resolved){return $resolved}
    throw 'SessionGame-Win64-Shipping.exe was not found under the selected path.'
}
function Assert-NoReparse([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            if(((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Refusing a junction/symlink path: $cursor"}
        }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor){break}; $cursor=$parent
    }
}
function Safe-Path([string]$Root,[string]$Relative) {
    if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Unsafe relative path.'}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Path escapes the game directory.'}
    Assert-NoReparse $path
    return $path
}
function Get-Context([string]$Root) {
    $classic=Test-Path -LiteralPath (Safe-Path $Root 'UE4SS.dll')
    $nested=Test-Path -LiteralPath (Safe-Path $Root 'ue4ss\UE4SS.dll')
    if($classic -and $nested){throw 'Two UE4SS installations detected. Resolve this before installing.'}
    $relative=if($nested){'ue4ss\Mods'}else{'Mods'}
    $runtime=if($nested){'ue4ss'}else{''}
    $settings=Safe-Path $Root $(if($nested){'ue4ss\UE4SS-settings.ini'}else{'UE4SS-settings.ini'})
    if(Test-Path -LiteralPath $settings){
        foreach($line in [IO.File]::ReadAllLines($settings)){
            if($line -match '^\s*ModsFolderPath\s*=\s*([^;]+)'){
                if(-not [string]::IsNullOrWhiteSpace($Matches[1])){throw 'Custom ModsFolderPath is configured. This installer will not modify an external/custom Mods folder.'}
            }
        }
    }
    return @{Root=$Root;ModsRelative=$relative;Mods=(Safe-Path $Root $relative);RuntimeRelative=$runtime;ExistingRuntime=($classic -or $nested)}
}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Read-Text([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return ''}
    return [IO.File]::ReadAllText($Path,$script:Utf8)
}
function Write-Text([string]$Path,[string]$Text) {
    # Keep a UTF8 BOM when one existed; preserve all unrelated lines verbatim.
    $bom=$false
    if(Test-Path -LiteralPath $Path){$bytes=[IO.File]::ReadAllBytes($Path);$bom=$bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191}
    [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($bom))
}
function Set-ModRow([string]$Text,[bool]$Enable) {
    $pattern='(?im)^[\t ]*SessionFPP[\t ]*:[^\r\n]*(?:\r?\n|$)'
    if(-not $Enable){return [regex]::Replace($Text,$pattern,'')}
    $newline=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
    if([regex]::IsMatch($Text,$pattern)){
        # Collapse duplicate rows for our own mod only.
        $Text=[regex]::Replace($Text,$pattern,'')
    }
    if($Text.Length -gt 0 -and -not $Text.EndsWith("`n")){$Text+=$newline}
    return $Text+'SessionFPP : 1'+$newline
}
function Get-OtherMods($Context) {
    $found=[Collections.Generic.List[string]]::new()
    if(Test-Path -LiteralPath $Context.Mods){
        foreach($entry in Get-ChildItem -LiteralPath $Context.Mods -Force){
            if($entry.Name -notin @($script:ModName,'mods.txt','mods.json')){$found.Add($entry.Name)}
        }
        $list=Join-Path $Context.Mods 'mods.txt'
        if(Test-Path -LiteralPath $list){
            foreach($line in [IO.File]::ReadAllLines($list)){
                if($line -match '^\s*([^;#:\s][^:]*)\s*:\s*[01]'){
                    if($Matches[1].Trim() -ne $script:ModName){$found.Add($Matches[1].Trim())}
                }
            }
        }
        $jsonList=Join-Path $Context.Mods 'mods.json'
        if(Test-Path -LiteralPath $jsonList){$found.Add('mods.json (external mod configuration)')}
        $own=Join-Path $Context.Mods $script:ModName
        if(Test-Path -LiteralPath $own){
            foreach($entry in Get-ChildItem -LiteralPath $own -Force){
                if($entry.Name -notin @('dlls','enabled.txt','.install-state.json')){$found.Add('Additional file in mod directory: '+$entry.Name)}
            }
            $dlls=Join-Path $own 'dlls'
            if(Test-Path -LiteralPath $dlls){foreach($entry in Get-ChildItem -LiteralPath $dlls -Force){if($entry.Name -ne 'main.dll'){$found.Add('Additional DLL/directory: '+$entry.Name)}}}
        }
    }
    foreach($name in @('dxgi.dll','dinput8.dll','xinput1_3.dll','winmm.dll','version.dll','ddraw.dll','UnrealModPlugins','modding')){
        if(Test-Path -LiteralPath (Safe-Path $Context.Root $name)){$found.Add($name)}
    }
    # Preserve the runtime if a different layout has gained any mod files too.
    $alternate=if($Context.ModsRelative -eq 'Mods'){'ue4ss\Mods'}else{'Mods'}
    $other=Safe-Path $Context.Root $alternate
    if((Test-Path -LiteralPath $other) -and @(Get-ChildItem -LiteralPath $other -Force).Count -gt 0){$found.Add($alternate)}
    return $found.ToArray()
}
function Remove-Empty([string]$Path) {
    if((Test-Path -LiteralPath $Path) -and @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0){Remove-Item -LiteralPath $Path -Force}
}
function Read-State([string]$Path,[string]$Root) {
    if(-not (Test-Path -LiteralPath $Path)){return $null}
    $state=(Read-Text $Path)|ConvertFrom-Json
    if($state.Schema -ne 1 -or $state.Mod -ne $script:ModName -or $state.GameRoot -ne $Root){throw 'Invalid or mismatched install ownership record.'}
    foreach($file in $state.RuntimeFiles){
        if($file.Path -notin @('UE4SS.dll','dwmapi.dll','UE4SS-settings.ini') -or $file.Sha256 -notmatch '^[0-9A-Fa-f]{64}$'){throw 'Unsafe runtime ownership record.'}
    }
    return $state
}
