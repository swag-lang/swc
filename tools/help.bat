@echo off
setlocal DisableDelayedExpansion
set "compiler=%~dp0..\bin\swc.exe"
set "arguments=%*"
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
if /i "%~1"=="dm" (
    set "compiler=%~dp0..\bin\swc.dm.exe"
    for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
)
if /i "%arguments%"=="-h" goto usage
if /i "%arguments%"=="--help" goto usage
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
pushd "%~dp0.."
"%compiler%" doc --workspace bin\std --doc-output-dir bin\help --rebuild --num-cores 3 %arguments%
set "result=%ERRORLEVEL%"
if not "%result%"=="0" goto done
"%compiler%" doc --workspace bin\reference --doc-output-dir bin\help --rebuild --num-cores 3 %arguments%
set "result=%ERRORLEVEL%"
:done
popd
exit /b %result%
:usage
echo Usage: help.bat [dm] [swc options]
exit /b 0
