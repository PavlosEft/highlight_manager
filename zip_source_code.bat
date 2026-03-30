@echo off
setlocal
for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
set "GREEN=%ESC%[32m"
set "RED=%ESC%[31m"
set "RESET=%ESC%[0m"

REM --- 0. FORCE CORRECT WORKING DIRECTORY ---
cd /d "%~dp0"

echo ==================================================
echo   BACKUP ZIP (Selected Files)
echo ==================================================

REM --- 1. GET DATE & TIME ---
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format 'dd-MM-yyyy_HH-mm-ss'"') do set "TS=%%I"

set "SUFFIX="
if "%~1"=="OK" set "SUFFIX=(OK)"

set "ZIP_NAME=SourceCode_%TS%%SUFFIX%.zip"

REM --- 2. MANAGE OLD BACKUPS ---
if not exist "Backups\" (
    echo [INFO] Creating Backups folder...
    mkdir "Backups"
)

if exist "SourceCode_*.zip" (
    echo [INFO] Moving old archives to Backups...
    move "SourceCode_*.zip" "Backups\" >nul
)

REM --- 3. CREATE NEW ZIP ---
echo [INFO] Creating new archive: %ZIP_NAME%

set "TARGETS="
set "TARGETS=%TARGETS% "lib\main.dart""
set "TARGETS=%TARGETS% "tool\dev_server.dart""
set "TARGETS=%TARGETS% "AI_INSTRUCTIONS.txt""
set "TARGETS=%TARGETS% "pubspec.yaml""
set "TARGETS=%TARGETS% "start_dev.bat""
set "TARGETS=%TARGETS% "android\app\src\main\kotlin\com\example\highlight_manager""

tar.exe -a -c -f "%ZIP_NAME%" %TARGETS%

if %ERRORLEVEL% EQU 0 (
    echo.
    echo %GREEN%[OK] Backup completed successfully!%RESET%
    echo [INFO] File saved as: %ZIP_NAME%
) else (
    echo.
    echo %RED%[ERROR] Backup failed. Check if all target files exist.%RESET%
    pause
)