@echo off
title Clean Workspace
setlocal
for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
set "GREEN=%ESC%[32m"
set "RED=%ESC%[31m"
set "RESET=%ESC%[0m"

echo ========================================================
echo   WORKSPACE CLEANUP OPTIONS
echo ========================================================
echo [1] Soft Clean (Delete .dart_tool ^& offline pub get)
echo [2] Deep Clean (Delete build, gradle stop, full flutter clean)
echo [3] Cancel
echo ========================================================
set /p choice="Choose (1, 2, 3): "

if "%choice%"=="1" goto quick
if "%choice%"=="2" goto deep
goto end

:quick
echo.
echo %GREEN%Starting Soft Clean...%RESET%
echo [1/3] Killing processes...
call kill_all.bat
echo [2/3] Deleting .dart_tool folder...
if exist .dart_tool rmdir /s /q .dart_tool
echo [3/3] Running flutter pub get --offline...
call flutter pub get --offline
goto finish

:deep
echo.
echo %GREEN%Starting Deep Clean...%RESET%
echo [1/5] Killing processes...
call kill_all.bat
echo [2/5] Stopping Gradle daemon...
if exist android cd android && call gradlew.bat --stop && cd ..
echo [3/5] Deleting temporary folders...
if exist build rmdir /s /q build
if exist .dart_tool rmdir /s /q .dart_tool
echo [4/5] Running flutter clean...
call flutter clean
echo [5/5] Running flutter pub get...
call flutter pub get
goto finish

:finish
echo ========================================================
echo %GREEN%Cleanup completed successfully!%RESET%
echo ========================================================
echo 1 > tool\.force_build
start start_dev.bat
exit

:end
echo.
echo %RED%Process cancelled. (Server continues to run)%RESET%
timeout /t 3 >nul
exit