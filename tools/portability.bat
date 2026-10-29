@echo off
setlocal
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
set "found="
for /r "%~dp0" %%F in (*.swgs) do set "found=%%F"
if defined found (
    echo error: Swag script launchers remain under tools: "%found%"
    exit /b 1
)
echo tools portability check passed: no .swgs launchers remain
exit /b 0
:usage
echo Usage: portability.bat
echo Checks that no .swgs launcher remains under tools/.
exit /b 0
