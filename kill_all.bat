@echo off
setlocal
for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
set "RED=%ESC%[31m"
set "RESET=%ESC%[0m"

echo ========================================================
echo %RED%[PANIC BUTTON] Killing all processes...%RESET%
echo ========================================================

:: 1. Kill the old Guardian first
wmic process where "name='powershell.exe' and commandline like '%%SmartGuardian%%'" delete >nul 2>&1

:: 2. Kill core tools
taskkill /F /IM dart.exe /T >nul 2>&1
taskkill /F /IM flutter.bat /T >nul 2>&1
taskkill /F /IM adb.exe /T >nul 2>&1
taskkill /F /IM java.exe /T >nul 2>&1
taskkill /F /IM scrcpy.exe /T >nul 2>&1

:: 3. Kill Logs ONLY! (Not the Server)
taskkill /F /FI "WINDOWTITLE eq Flutter_Smart_Logs*" /T >nul 2>&1