@echo off
chcp 65001 >nul
setlocal

echo ==================================================
echo   BACKUP ZIP (Selected Files)
echo ==================================================

REM --- 1. ΥΠΟΛΟΓΙΣΜΟΣ ΗΜΕΡΟΜΗΝΙΑΣ & ΩΡΑΣ (ΜΕ ΔΕΥΤΕΡΟΛΕΠΤΑ) ---
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "datetime=%%I"

set "YYYY=%datetime:~0,4%"
set "MM=%datetime:~4,2%"
set "DD=%datetime:~6,2%"
set "HH=%datetime:~8,2%"
set "Min=%datetime:~10,2%"
set "Sec=%datetime:~12,2%"

REM Νέο όνομα χωρίς το "Strict" και με δευτερόλεπτα
set "ZIP_NAME=SourceCode_%DD%-%MM%-%YYYY%_%HH%-%Min%-%Sec%.zip"

REM --- 2. ΔΙΑΧΕΙΡΙΣΗ ΠΑΛΙΩΝ BACKUPS ---
if not exist "Backups" (
    echo [INFO] Creating Backups folder...
    mkdir "Backups"
)

REM Μετακινούμε ΟΛΑ τα προηγούμενα zip (SourceCode_*.zip) στο Backups
REM Έτσι στο root θα μείνει μόνο το καινούργιο που θα φτιαχτεί παρακάτω.
if exist "SourceCode_*.zip" (
    echo [INFO] Moving old archives to Backups...
    move "SourceCode_*.zip" "Backups\" >nul
)

REM --- 3. ΔΗΜΙΟΥΡΓΙΑ ΝΕΟΥ ZIP ---
echo [INFO] Creating new archive: %ZIP_NAME%

tar.exe -a -c -f "%ZIP_NAME%" ^
    "lib" ^
    "tool" ^
    "AI_INSTRUCTIONS.txt" ^
    "pubspec.yaml" ^
    "start_dev.bat"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] Το Backup ολοκληρώθηκε επιτυχώς!
    echo [INFO] Το αρχείο βρίσκεται εδώ: %ZIP_NAME%
) else (
    echo.
    echo [ERROR] Κάτι πήγε στραβά (ίσως λείπει κάποιο αρχείο;)
)
