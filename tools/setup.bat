@echo off
setlocal

rem Registers the repository compiler directory in the current user's environment.
rem
rem     setup.bat

for %%I in ("%~dp0..\bin") do set "FULL_PATH=%%~fI"

rem Read current user PATH safely
set "UserPath="
for /f "usebackq tokens=2,*" %%A in (`reg query "HKCU\Environment" /v PATH 2^>nul`) do set "UserPath=%%B"

echo %UserPath% | find /i "%FULL_PATH%" >nul
if %errorlevel%==0 (
    echo "%FULL_PATH%" is already in PATH.
) else (
    echo Adding "%FULL_PATH%" to user PATH...
    if defined UserPath (
        setx PATH "%UserPath%;%FULL_PATH%"
    ) else (
        setx PATH "%FULL_PATH%"
    )
)

echo Setting SWAG_PATH to "%FULL_PATH%"...
setx SWAG_PATH "%FULL_PATH%"

echo Done. You may need to restart your terminal.
