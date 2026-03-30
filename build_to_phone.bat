@echo off
chcp 65001 >nul
setlocal
for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
set "GREEN=%ESC%[32m"
set "RESET=%ESC%[0m"

cd /d "%~dp0"

title Build ^& Push to Phone
echo ========================================================
echo Starting Build and transfer to phone...
echo ========================================================

echo 1. Building new APK (No clean for speed)...
call flutter build apk

echo 2. Installing to phone...
call flutter install

echo.
echo %GREEN%Done! You can unplug the cable.%RESET%
pause