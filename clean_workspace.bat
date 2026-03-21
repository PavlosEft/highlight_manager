@echo off
title Clean Workspace
echo ========================================================
echo 🧹 EPILOGES KATHARISMOU WORKSPACE
echo ========================================================
echo [1] Soft Clean (Diagrafi mono .dart_tool ^& offline pub get)
echo [2] Deep Clean (Diagrafi build, gradle stop, plires flutter clean)
echo [3] Akirosi
echo ========================================================
set /p choice="DialeKse (1, 2, 3): "

if "%choice%"=="1" goto quick
if "%choice%"=="2" goto deep
goto end

:quick
echo.
echo 🧹 Ekkinisi Soft Clean...
echo [1/3] Skotonontai oi diergasies...
call kill_all.bat
echo [2/3] Diagrafi fakelou .dart_tool...
if exist .dart_tool rmdir /s /q .dart_tool
echo [3/3] Ektelesi flutter pub get --offline...
call flutter pub get --offline
goto finish

:deep
echo.
echo 🧹 Ekkinisi Deep Clean...
echo [1/5] Skotonontai oi diergasies...
call kill_all.bat
echo [2/5] Stamatima tou Gradle daemon...
if exist android cd android && call gradlew.bat --stop && cd ..
echo [3/5] Diagrafi prosorinon fakelon...
if exist build rmdir /s /q build
if exist .dart_tool rmdir /s /q .dart_tool
echo [4/5] Ektelesi flutter clean...
call flutter clean
echo [5/5] Ektelesi flutter pub get...
call flutter pub get
goto finish

:finish
echo ========================================================
echo ✅ O katharismos oloklirothike me epitixia!
echo ========================================================
echo 1 > tool\.force_build
start start_dev.bat
exit

:end
echo.
echo 🚫 I diadikasia akirothike. (O server sinexizei na trexei kanonika)
timeout /t 3 >nul
exit