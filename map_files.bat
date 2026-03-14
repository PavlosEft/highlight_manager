@echo off
:: Ορισμός κωδικοποίησης UTF-8 για να διαβάζει σωστά τα ελληνικά ονόματα
chcp 65001 >nul
setlocal enabledelayedexpansion

set "OutputFile=FileList.txt"
set "Count=0"

:: Διαγραφή του προηγούμενου αρχείου txt (αν υπάρχει από παλαιότερη εκτέλεση)
if exist "%OutputFile%" del "%OutputFile%"

echo Δημιουργία λίστας αρχείων... Παρακαλώ περιμένετε.

:: Σάρωση όλων των αρχείων και υποφακέλων (το /r κάνει την αναζήτηση στους υποφακέλους)
for /r %%I in (*) do (
    :: Εξαιρούμε από τη λίστα το ίδιο το bat αρχείο και το FileList.txt
    if /I not "%%~nxI"=="%OutputFile%" if /I not "%%~nxI"=="%~nx0" (
        echo %%~nxI    -    %%~fI >> "%OutputFile%"
        set /a Count+=1
    )
)

:: Προσθήκη του συνολικού αριθμού στο τέλος του txt
echo. >> "%OutputFile%"
echo ========================================================= >> "%OutputFile%"
echo Σύνολο αρχείων που βρέθηκαν: !Count! >> "%OutputFile%"

echo.
echo Η διαδικασία ολοκληρώθηκε επιτυχώς! 
echo Βρέθηκαν συνολικά !Count! αρχεία.
echo Μπορείς να δεις το αρχείο "%OutputFile%" στον ίδιο φάκελο.
pause