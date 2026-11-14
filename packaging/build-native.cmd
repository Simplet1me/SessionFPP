@echo off
setlocal
cd /d "%~dp0.."
if defined VSCMD_VER goto configured
set "vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%vswhere%" (
  echo Install Visual Studio C++ build tools or run from an x64 developer command prompt.
  exit /b 1
)
for /f "usebackq tokens=*" %%i in (`"%vswhere%" -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "history_vs=%%i"
if not defined history_vs (
  echo Visual Studio x64 C++ build tools were not found.
  exit /b 1
)
call "%history_vs%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1
:configured
cmake -S . -B build/native -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 1
cmake --build build/native
exit /b %errorlevel%
