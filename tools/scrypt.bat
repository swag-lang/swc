@echo off
setlocal

rem Runs the privileged sCrypt/WinFsp end-to-end sandbox, then restores a normal build.
rem
rem     scrypt.bat [dm]
rem
rem The integration build mounts a real volume, so it is kept out of the default test set and
rem run on demand. The final rebuild is what puts a plain sCrypt back in the output directory.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help

set "APP_DIR=%ROOT%\bin\apps\.output\sCrypt\executable\release\%TARGET_ARCH%"
call "%TOOLS_DIR%apps.bat" %MODE_ARG% build sCrypt -bc release --tag SCrypt.Integration --rebuild || exit /b 1

if exist "%APP_DIR%\sCrypt-integration-result.txt" del /Q "%APP_DIR%\sCrypt-integration-result.txt"
"%APP_DIR%\sCrypt.exe"
set "TEST_RESULT=%ERRORLEVEL%"

if exist "%APP_DIR%\sCrypt-integration-result.txt" type "%APP_DIR%\sCrypt-integration-result.txt"
echo.

call "%TOOLS_DIR%apps.bat" %MODE_ARG% build sCrypt -bc release --rebuild
if errorlevel 1 if "%TEST_RESULT%"=="0" set "TEST_RESULT=1"
exit /b %TEST_RESULT%

:help
echo Runs the privileged sCrypt/WinFsp end-to-end sandbox.
echo.
echo   scrypt.bat [dm]
echo.
echo Builds sCrypt with the SCrypt.Integration tag, runs it, prints its report, then
echo rebuilds a normal sCrypt. It mounts a real volume, so it stays out of tests.bat.
exit /b 0
