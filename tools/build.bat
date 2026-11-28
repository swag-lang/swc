@echo off
setlocal DisableDelayedExpansion
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
set "arguments=%*"
if /i "%~1"=="dm" for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
if /i "%~1"=="dm" (
    call "%~dp0std.bat" dm build %arguments%
) else (
    call "%~dp0std.bat" build %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0examples.bat" dm build %arguments%
) else (
    call "%~dp0examples.bat" build %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0apps.bat" dm build %arguments%
) else (
    call "%~dp0apps.bat" build %arguments%
)
if errorlevel 1 exit /b 1
if /i "%~1"=="dm" (
    call "%~dp0reference.bat" dm build %arguments%
) else (
    call "%~dp0reference.bat" build %arguments%
)
if errorlevel 1 exit /b 1
exit /b 0
:usage
echo Usage: build.bat [dm] [swc options]
echo Builds the standard library, examples, applications, and reference.
exit /b 0
