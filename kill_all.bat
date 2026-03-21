@echo off
echo ========================================================
echo 💀 [PANIC BUTTON] Skotonontai oles oi diergasies...
echo ========================================================

:: 1. Σκοτώνουμε πρώτα τον παλιό Φύλακα
wmic process where "name='powershell.exe' and commandline like '%%EksipnosFylakas%%'" delete >nul 2>&1

:: 2. Σκοτώνουμε τα βασικά εργαλεία
taskkill /F /IM dart.exe /T >nul 2>&1
taskkill /F /IM flutter.bat /T >nul 2>&1
taskkill /F /IM adb.exe /T >nul 2>&1
taskkill /F /IM java.exe /T >nul 2>&1
taskkill /F /IM scrcpy.exe /T >nul 2>&1

:: 3. Σκοτώνουμε ΜΟΝΟ τα Logs! (Όχι τον Server)
taskkill /F /FI "WINDOWTITLE eq Flutter_Smart_Logs*" /T >nul 2>&1
