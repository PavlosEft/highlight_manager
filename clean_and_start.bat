@echo off
title Flutter Clean and Start
echo ====================================================
echo Καθαρισμος της cache (flutter clean)...
echo Παρακαλω περιμενετε, αυτο μπορει να παρει λιγο χρονο.
echo ====================================================
call flutter clean
echo.
echo Ξεκινάει ο Dev Server...
cmd /k "dart run tool\dev_server.dart"