@echo off
setlocal

if "%~1"=="" goto :usage
if "%~2"=="" goto :usage

set "LABEL=%~1"
set "EXE=%~2"
for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "EXTRA=%3 %4 %5 %6 %7 %8 %9"

call "%TOOLS_DIR%_suite.bat" syntax %EXE% --cfg release %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg release --no-optimize %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg release --optimize %EXTRA%

call "%TOOLS_DIR%_suite.bat" syntax %EXE% --cfg debug %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg debug --no-optimize %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg debug --optimize %EXTRA%

call "%TOOLS_DIR%_suite.bat" syntax %EXE% --cfg fast-debug %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg fast-debug --no-optimize %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg fast-debug --optimize %EXTRA%

call "%TOOLS_DIR%_suite.bat" syntax %EXE% --cfg fast-compile %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg fast-compile --no-optimize %EXTRA%
call "%TOOLS_DIR%_suite.bat" sema %EXE% --cfg fast-compile --optimize %EXTRA%

exit /b 0

:usage
exit /b 2
