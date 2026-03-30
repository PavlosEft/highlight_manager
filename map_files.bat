@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

for /f %%e in ('echo prompt $E ^| cmd') do set "ESC=%%e"
set "GREEN=%ESC%[32m"
set "RESET=%ESC%[0m"

set "OutputFile=FileList.txt"
set "Count=0"

if exist "%OutputFile%" del "%OutputFile%"

echo Creating file list... Please wait.

:: Scan all files and subfolders
for /r %%I in (*) do (
    :: Exclude the bat file itself and the OutputFile
    if /I not "%%~nxI"=="%OutputFile%" if /I not "%%~nxI"=="%~nx0" (
        echo %%~nxI    -    %%~fI >> "%OutputFile%"
        set /a Count+=1
    )
)

:: Add total count to the end
echo. >> "%OutputFile%"
echo ========================================================= >> "%OutputFile%"
echo Total files found: !Count! >> "%OutputFile%"

echo.
echo %GREEN%Process completed successfully!%RESET%
echo Found total !Count! files.
echo You can view the file "%OutputFile%" in this folder.
pause