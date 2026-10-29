@echo off
setlocal DisableDelayedExpansion

set "tool=%~1"
for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"

set "compiler=%~dp0..\bin\swc.exe"
for /f "tokens=1,*" %%A in ("%arguments%") do (
    set "first=%%A"
    set "remaining=%%B"
)
if /i "%first%"=="dm" (
    set "compiler=%~dp0..\bin\swc.dm.exe"
    set "arguments=%remaining%"
)

for /f "tokens=1,*" %%A in ("%arguments%") do (
    set "first=%%A"
    set "remaining=%%B"
)
if /i "%first%"=="-h" goto usage
if /i "%first%"=="--help" goto usage
set "action=build"
if /i "%tool%"=="std" if /i "%first%"=="test" set "action=test"
if /i "%tool%"=="examples" if /i "%first%"=="build" set "action=build"
if /i "%tool%"=="examples" if /i "%first%"=="run" set "action=run"
if /i "%tool%"=="examples" if /i "%first%"=="test" set "action=test"
if /i "%tool%"=="examples" if /i "%first%"=="smoke" set "action=smoke"
if /i "%tool%"=="apps" if /i "%first%"=="build" set "action=build"
if /i "%tool%"=="apps" if /i "%first%"=="run" set "action=run"
if /i "%tool%"=="apps" if /i "%first%"=="test" set "action=test"
if /i "%tool%"=="apps" if /i "%first%"=="smoke" set "action=smoke"
if /i "%tool%"=="reference" set "action=test"
if /i "%tool%"=="reference" if /i "%first%"=="build" set "action=build"
if /i "%tool%"=="reference" if /i "%first%"=="test" set "action=test"

set "module="
set "options=%arguments%"
if /i "%first%"=="build" set "options=%remaining%"
if /i "%first%"=="run" set "options=%remaining%"
if /i "%first%"=="test" set "options=%remaining%"
if /i "%first%"=="smoke" set "options=%remaining%"
if /i "%tool%"=="reference" set "options=%arguments%"
if /i "%tool%"=="reference" if /i "%first%"=="build" set "options=%remaining%"
if /i "%tool%"=="reference" if /i "%first%"=="test" set "options=%remaining%"

if not defined options goto invoke
for /f "tokens=1,*" %%A in ("%options%") do (
    set "firstOption=%%A"
    set "optionTail=%%B"
)
if not "%firstOption:~0,1%"=="-" if /i not "%firstOption%"=="dm" (
    if /i not "%firstOption%"=="build" if /i not "%firstOption%"=="run" if /i not "%firstOption%"=="test" if /i not "%firstOption%"=="smoke" (
        set "module=%firstOption%"
        set "options=%optionTail%"
    )
)

:invoke
set "workspace=%~dp0..\bin\%tool%"
if /i "%tool%"=="std" set "workspace=%~dp0..\bin\std"
if /i "%tool%"=="examples" set "workspace=%~dp0..\bin\examples"
if /i "%tool%"=="apps" set "workspace=%~dp0..\bin\apps"
if /i "%tool%"=="reference" set "workspace=%~dp0..\bin\reference"
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
if /i "%tool%"=="apps" if /i "%action%"=="run" if not defined module (
    echo error: running an application needs its name
    exit /b 1
)
set "appTest="
set "appRunArguments="
if /i "%tool%"=="apps" if /i "%action%"=="test" set "appTest=--no-test-jit"
if /i "%tool%"=="apps" if /i not "%action%"=="build" if /i "%module%"=="swagprism" set "appRunArguments=--run-arg=--compiler="%compiler%" --run-arg=--compiler-workers=6"
if defined module (
    "%compiler%" %action% --workspace "%workspace%" --workspace-module "%module%" %appTest% %appRunArguments% --num-cores 6 %options%
) else (
    "%compiler%" %action% --workspace "%workspace%" %appTest% %appRunArguments% --num-cores 6 %options%
)
set "result=%ERRORLEVEL%"
if not "%result%"=="0" exit /b %result%
if /i "%tool%"=="apps" if /i "%action%"=="build" call :packageVault
if errorlevel 1 exit /b 1
exit /b %result%

:usage
if /i "%tool%"=="std" echo Usage: std.bat [dm] [build^|test] [module] [swc options]
if /i "%tool%"=="reference" echo Usage: reference.bat [dm] [build^|test] [swc options]
if /i "%tool%"=="examples" echo Usage: examples.bat [dm] [build^|run^|test^|smoke] [module] [swc options]
if /i "%tool%"=="apps" echo Usage: apps.bat [dm] [build^|run^|test^|smoke] [application] [swc options]
echo Use -h with the compiler for compiler command options.
exit /b 0

:packageVault
echo(%module%| findstr /i /x "swagvault" >nul
if errorlevel 1 if defined module exit /b 0
set "config=devmode"
echo(%options%| findstr /i /c:"-bc release" /c:"--build-cfg release" >nul && set "config=release"
echo(%options%| findstr /i /c:"--debug" >nul && set "config=%config%-debug"
set "appDir=%~dp0..\bin\apps\.output\swagvault\executable\%config%\x86_64"
set "vendor=%~dp0..\bin\apps\modules\swagvault\vendor\winfsp\runtime"
if not exist "%appDir%\swagvault.exe" exit /b 0
copy /y "%vendor%\winfsp-x64.dll" "%appDir%\winfsp-x64.dll" >nul
if errorlevel 1 exit /b 1
copy /y "%vendor%\winfsp-x64.sys" "%appDir%\winfsp-x64.sys" >nul
if errorlevel 1 exit /b 1
copy /y "%~dp0..\bin\apps\modules\swagvault\LICENCE.md" "%appDir%\LICENCE.md" >nul
if errorlevel 1 exit /b 1
copy /y "%~dp0..\bin\apps\modules\swagvault\THIRDPARTY.md" "%appDir%\THIRDPARTY.md" >nul
exit /b %errorlevel%
