@echo off
setlocal
for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
set "GREEN=%ESC%[32m"
set "RESET=%ESC%[0m"

echo Initial Cleanup...
call kill_all.bat

title Control Panel - Smart Dev Server

echo.
echo Restarting ADB (to prevent connection loss)...
adb start-server
timeout /t 3 /nobreak > NUL

echo Starting Device Mirror...
start cmd /c "C:\Users\Lenovo\Desktop\device-mirror\run-mirror.bat"

echo Activating Smart Watcher...
:: The Watcher now rapidly checks the SPECIFIC server process
start powershell -WindowStyle Hidden -Command "$dummy='SmartGuardian'; Start-Sleep -Seconds 3; while (Get-CimInstance Win32_Process -Filter \"Name='dart.exe' and CommandLine like '%%dev_server.dart%%'\") { Start-Sleep -Seconds 1 }; Start-Process -WindowStyle Hidden cmd.exe -ArgumentList '/c kill_all.bat'"

echo %GREEN%Starting Unified Control Panel...%RESET%
dart run tool\dev_server.dart
pause