@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" echo Installation failed. Read the message above.
pause
exit /b %result%
