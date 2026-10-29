@echo off
setlocal
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
set "bin=%~dp0..\bin"
for %%I in ("%bin%") do set "bin=%%~fI"
set "userPath="
set "pathType=REG_EXPAND_SZ"
for /f "tokens=1,2,*" %%A in ('reg query HKCU\Environment /v Path 2^>nul') do (
    if /i "%%B"=="REG_EXPAND_SZ" set "userPath=%%C"
    if /i "%%B"=="REG_SZ" (
        set "userPath=%%C"
        set "pathType=REG_SZ"
    )
)
if not defined userPath set "userPath="
if defined userPath (
    echo;%userPath%; | findstr /i /l /c:";%bin%;" >nul
    if errorlevel 1 reg add HKCU\Environment /v Path /t %pathType% /d "%userPath%;%bin%" /f >nul
) else (
    reg add HKCU\Environment /v Path /t REG_EXPAND_SZ /d "%bin%" /f >nul
)
if errorlevel 1 exit /b %errorlevel%
setx SWAG_PATH "%bin%" >nul
if errorlevel 1 exit /b %errorlevel%
echo Registered "%bin%" in the user PATH and set SWAG_PATH.
echo Restart the terminal to use the updated environment.
exit /b 0
:usage
echo Usage: setup.bat
exit /b 0
