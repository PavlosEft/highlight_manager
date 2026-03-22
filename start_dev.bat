@echo off

echo 🧹 Arhikos Katharismos...
call kill_all.bat

:: ΤΩΡΑ του δίνουμε το όνομα, ΑΦΟΥ έχει τελειώσει ο καθαρισμός
title Control Panel - Smart Dev Server

echo.
echo 🔌 Epanekkinisi tou ADB (gia na min xathei i sindesi)...
adb start-server
timeout /t 3 /nobreak > NUL

echo 🚀 Starting Device Mirror...
start cmd /c "C:\Users\Lenovo\Desktop\device-mirror\run-mirror.bat"

echo 🛡️ Energopoiisi Eksipnou Fylaka (Watcher)...
:: Ο Φύλακας πλέον ελέγχει ταχύτατα τη ΣΥΓΚΕΚΡΙΜΕΝΗ διεργασία του server
start powershell -WindowStyle Hidden -Command "$dummy='EksipnosFylakas'; Start-Sleep -Seconds 3; while (Get-CimInstance Win32_Process -Filter \"Name='dart.exe' and CommandLine like '%%dev_server.dart%%'\") { Start-Sleep -Seconds 1 }; Start-Process -WindowStyle Hidden cmd.exe -ArgumentList '/c kill_all.bat'"

echo ⚡ Starting Unified Control Panel...
dart run tool\dev_server.dart
pause