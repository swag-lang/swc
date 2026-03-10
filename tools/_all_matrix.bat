@echo off
setlocal

if "%~1"=="" goto :usage
if "%~2"=="" goto :usage

set "LABEL=%~1"
set "EXE=%~2"
for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "EXTRA=%3 %4 %5 %6 %7 %8 %9"

call "%TOOLS_DIR%_suite.bat" test %EXE% --cfg release %EXTRA%
call "%TOOLS_DIR%_suite.bat" test %EXE% --cfg debug %EXTRA%
call "%TOOLS_DIR%_suite.bat" test %EXE% --cfg fast-debug %EXTRA%
call "%TOOLS_DIR%_suite.bat" test %EXE% --cfg fast-compile %EXTRA%

exit /b 0

:usage
exit /b 2
