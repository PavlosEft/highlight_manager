@echo off
title Clean Workspace
echo ========================================================
echo 🧹 EKKINISI KATHARISMOU WORKSPACE...
echo ========================================================
echo.

echo [1/5] Kleisimo energon diergasion (Dart, Flutter, AI Patcher)...
taskkill /F /IM dart.exe /T >nul 2>&1
taskkill /F /IM flutter.bat /T >nul 2>&1

echo [2/5] Stamatima tou Gradle daemon...
if exist android cd android && call gradlew.bat --stop && cd ..

echo [3/5] Diagrafi prosorinon fakelon (build, .dart_tool)...
if exist build rmdir /s /q build
if exist .dart_tool rmdir /s /q .dart_tool

echo [4/5] Ektelesi flutter clean...
call flutter clean

echo [5/5] Ektelesi flutter pub get...
call flutter pub get

echo.
echo ========================================================
echo ✅ O katharismos oloklirothike me epitixia!
echo Epanekkinisi tou perivallontos (start_dev.bat)...
echo ========================================================
echo 1 > tool\.force_build
start start_dev.bat
exit
