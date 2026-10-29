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
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
"%compiler%" format -d "%~dp0..\bin" -d "%~dp0..\bench\src" --num-cores 6 %arguments%
exit /b %errorlevel%
:usage
echo Usage: format.bat [dm] [swc options]
exit /b 0
