@echo off
setlocal DisableDelayedExpansion
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
call "%~dp0portability.bat"
if errorlevel 1 exit /b 1
set "arguments=%*"
if /i "%~1"=="dm" for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
if /i "%~1"=="dm" (
    call "%~dp0unittests.bat" dm %arguments%
) else (
    call "%~dp0unittests.bat" %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0std.bat" dm test %arguments%
) else (
    call "%~dp0std.bat" test %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0examples.bat" dm test %arguments%
) else (
    call "%~dp0examples.bat" test %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0apps.bat" dm test %arguments%
) else (
    call "%~dp0apps.bat" test %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0reference.bat" dm test %arguments%
) else (
    call "%~dp0reference.bat" test %arguments%
)
exit /b %errorlevel%
:usage
echo Usage: tests.bat [dm] [swc options]
echo Runs compiler input suites and workspace tests.
exit /b 0
