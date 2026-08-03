@echo off
setlocal

rem Runs the privileged sCrypt/WinFsp end-to-end sandbox, then restores a normal build.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

set "MODE_ARG="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

set "APP_DIR=%ROOT%\bin\apps\.output\sCrypt\executable\release\%TARGET_ARCH%"
call "%TOOLS_DIR%manage-applications-workspace.bat" %MODE_ARG% build -m sCrypt -bc release --tag SCrypt.Integration --rebuild || exit /b 1

if exist "%APP_DIR%\sCrypt-integration-result.txt" del /Q "%APP_DIR%\sCrypt-integration-result.txt"
"%APP_DIR%\sCrypt.exe"
set "TEST_RESULT=%ERRORLEVEL%"

if exist "%APP_DIR%\sCrypt-integration-result.txt" type "%APP_DIR%\sCrypt-integration-result.txt"
echo.

call "%TOOLS_DIR%manage-applications-workspace.bat" %MODE_ARG% build -m sCrypt -bc release --rebuild
if errorlevel 1 if "%TEST_RESULT%"=="0" set "TEST_RESULT=1"
exit /b %TEST_RESULT%
