@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

if not exist "%TMP_ROOT%" mkdir "%TMP_ROOT%"
set "RSP=%TMP_ROOT%\format_bin_%SWC_MODE%.rsp"
del "%RSP%" >nul 2>nul

(
    for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command "Get-ChildItem -Path '%ROOT%\bin' -Recurse -Filter *.swg -File | ForEach-Object { '--file ""' + $_.FullName + '""' }"`) do @echo %%F
) > "%RSP%"

%SWC_EXE% format @%RSP%
set "ERR=%ERRORLEVEL%"

del "%RSP%" >nul 2>nul
exit /b %ERR%
