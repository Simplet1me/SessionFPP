param([string]$Version='0.2.0',[switch]$Rebuild)
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid release version.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dll=Join-Path $root 'build\native\main.dll'
if(-not (Test-Path -LiteralPath $dll)){throw 'Build the native DLL first.'}
$destination=Join-Path $root ('release\'+$Version)
$releaseBase=Join-Path $root 'release'
if((Test-Path -LiteralPath $releaseBase) -and ((Get-Item -LiteralPath $releaseBase).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refusing a junction/symlink release directory.'}
if(Test-Path -LiteralPath $destination){
    if(-not $Rebuild){throw 'Release directory already exists. Pass -Rebuild to regenerate this package.'}
    $expected=[IO.Path]::GetFullPath((Join-Path $root ('release\'+$Version)))
    if([IO.Path]::GetFullPath($destination) -ne $expected -or ((Get-Item -LiteralPath $destination).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe release cleanup path.'}
    # Delete only this explicitly selected generated version, never release itself.
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach($file in @('common.ps1','install.ps1','uninstall.ps1','Install.cmd','Uninstall.cmd')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('installer\'+$file)) -Destination (Join-Path $destination $file)
}
$payload=Join-Path $destination 'payload'
$provenance=Get-Content -LiteralPath (Join-Path $root 'third_party\ue4ss-runtime\PROVENANCE.json') -Raw|ConvertFrom-Json
foreach($entry in $provenance.files.PSObject.Properties){
    if((Get-FileHash -LiteralPath (Join-Path $root ('third_party\ue4ss-runtime\'+$entry.Name)) -Algorithm SHA256).Hash -ne $entry.Value){throw 'Bundled dependency changed: verify and update its provenance first.'}
}
New-Item -ItemType Directory -Path (Join-Path $payload 'mod\dlls'),(Join-Path $payload 'ue4ss') -Force | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $payload 'mod\dlls\main.dll')
[IO.File]::WriteAllBytes((Join-Path $payload 'mod\enabled.txt'),[byte[]]@())
foreach($file in @('UE4SS.dll','dwmapi.dll','UE4SS-settings.ini')){
    Copy-Item -LiteralPath (Join-Path $root ('third_party\ue4ss-runtime\'+$file)) -Destination (Join-Path $payload ('ue4ss\'+$file))
}
$files=@('mod\dlls\main.dll','mod\enabled.txt','ue4ss\UE4SS.dll','ue4ss\dwmapi.dll','ue4ss\UE4SS-settings.ini')|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash -LiteralPath (Join-Path $payload $_) -Algorithm SHA256).Hash}}
@{Version=$Version;Files=@($files)}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $payload 'manifest.json') -Encoding UTF8
foreach($file in @('LICENSE','LICENSE-EXCEPTION.txt')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $destination}
Copy-Item -LiteralPath (Join-Path $root 'third_party\ue4ss-runtime\LICENSE.txt') -Destination (Join-Path $destination 'UE4SS-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $root 'docs\USER-GUIDE.md') -Destination (Join-Path $destination 'README.md')
$source=Join-Path $destination 'Source'
New-Item -ItemType Directory -Path (Join-Path $source 'third_party'),(Join-Path $source 'packaging') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'native') -Destination $source -Recurse
foreach($folder in @('ue4ss','minhook')){Copy-Item -LiteralPath (Join-Path $root ('third_party\'+$folder)) -Destination (Join-Path $source 'third_party') -Recurse}
Copy-Item -LiteralPath (Join-Path $root 'third_party\README.md') -Destination (Join-Path $source 'third_party')
foreach($file in @('CMakeLists.txt','LICENSE','LICENSE-EXCEPTION.txt','README.md')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $source}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-native.cmd') -Destination (Join-Path $source 'packaging')
Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination $source -Recurse
$archive=Join-Path $destination ('SessionFPP-'+$Version+'.zip')
# Archive the publishable contents before adding the ZIP and checksum themselves.
Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $destination | Select-Object -ExpandProperty FullName) -DestinationPath $archive -CompressionLevel Optimal
$digest=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
[IO.File]::WriteAllText($archive+'.sha256',$digest+'  '+[IO.Path]::GetFileName($archive)+[Environment]::NewLine,[Text.Encoding]::ASCII)
Write-Output "Package: $archive"
Write-Output "SHA256: $digest"
