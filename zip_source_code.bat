@echo off
setlocal

REM --- 0. FORCE CORRECT WORKING DIRECTORY ---
cd /d "%~dp0"

echo ==================================================
echo   BACKUP ZIP (Selected Files)
echo ==================================================

REM --- 1. GET DATE & TIME (Safe PowerShell Method) ---
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format 'dd-MM-yyyy_HH-mm-ss'"') do set "TS=%%I"

REM Parameter Check (e.g., OK)
set "SUFFIX="
if "%~1"=="OK" set "SUFFIX=(OK)"

REM Final Zip Name
set "ZIP_NAME=SourceCode_%TS%%SUFFIX%.zip"

REM --- 2. MANAGE OLD BACKUPS ---
if not exist "Backups\" (
    echo [INFO] Creating Backups folder...
    mkdir "Backups"
)

REM Move previous zip files to Backups
if exist "SourceCode_*.zip" (
    echo [INFO] Moving old archives to Backups...
    move "SourceCode_*.zip" "Backups\" >nul
)

REM --- 3. CREATE NEW ZIP ---
echo [INFO] Creating new archive: %ZIP_NAME%

REM Ασφαλής Λίστα Αρχείων (Πρόσθεσε ή αφαίρεσε γραμμές εύκολα)
set "TARGETS="
set "TARGETS=%TARGETS% "lib\main.dart""
set "TARGETS=%TARGETS% "tool\dev_server.dart""
set "TARGETS=%TARGETS% "AI_INSTRUCTIONS.txt""
set "TARGETS=%TARGETS% "pubspec.yaml""
set "TARGETS=%TARGETS% "start_dev.bat""

tar.exe -a -c -f "%ZIP_NAME%" %TARGETS%

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] Backup completed successfully!
    echo [INFO] File saved as: %ZIP_NAME%
) else (
    echo.
    echo [ERROR] Backup failed. Check if all target files exist.
)