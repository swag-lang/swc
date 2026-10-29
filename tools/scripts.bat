@echo off
setlocal DisableDelayedExpansion
set "compiler=%~dp0..\bin\swc.exe"
set "action=run"
set "script="
set "arguments=%*"
if /i "%~1"=="dm" (
    set "compiler=%~dp0..\bin\swc.dm.exe"
    for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
)
set "first="
set "remaining="
for /f "tokens=1,*" %%A in ("%arguments%") do (
    set "first=%%A"
    set "remaining=%%B"
)
if /i "%first%"=="run" (
    set "action=run"
    set "arguments=%remaining%"
    set "first="
    set "remaining="
    for /f "tokens=1,*" %%A in ("%remaining%") do (
        set "first=%%A"
        set "remaining=%%B"
    )
) else if /i "%first%"=="smoke" (
    set "action=smoke"
    set "arguments=%remaining%"
    set "first="
    set "remaining="
    for /f "tokens=1,*" %%A in ("%remaining%") do (
        set "first=%%A"
        set "remaining=%%B"
    )
)
if /i "%first%"=="-h" goto usage
if /i "%first%"=="--help" goto usage
if defined first if not "%first:~0,1%"=="-" (
    set "script=%first%"
    set "arguments=%remaining%"
)
if not defined script set "action=smoke"
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
if defined script goto one
for %%S in ("%~dp0..\bin\examples\scripts\*.swgs") do if exist "%%~fS" (
    call :run "%%~nS"
    if errorlevel 1 exit /b 1
)
exit /b 0
:one
call :run "%script%"
exit /b %errorlevel%
:run
set "name=%~1"
if /i "%name:~-5%"==".swgs" set "name=%name:~0,-5%"
"%compiler%" %action% -f "%~dp0..\bin\examples\scripts\%name%.swgs" --num-cores 6 %arguments%
exit /b %errorlevel%
:usage
echo Usage: scripts.bat [dm] [run^|smoke] [script] [swc options]
exit /b 0
