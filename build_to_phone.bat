@echo off
:: Διορθώνει την εμφάνιση των emojis (UTF-8)
chcp 65001 >nul

:: Αλλάζει το directory (cd) αυτόματα στον φάκελο που βρίσκεται το ίδιο το .bat αρχείο
cd /d "%~dp0"

title Build ^& Push to Phone
echo ========================================================
echo 🚀 Ksekinima Build kai metafora sto kinito...
echo ========================================================

echo 2. Xtysimo neou APK (xoris clean gia na einai grigoro)...
call flutter build apk

echo 3. Egkatastasi sto kinito...
call flutter install

echo ✅ Oloklirothike! Mporeis na vgaleis to kalodio.
pause