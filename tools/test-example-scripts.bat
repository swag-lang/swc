@echo off
setlocal EnableDelayedExpansion

rem Smokes every standalone example script: each one runs for a bounded number of frames,
rem isolated from the machine, and the run has to finish without an error.
rem
rem A script declares no #test, so there is nothing for the test command to run. What is worth
rem proving about it is that it starts and keeps going, which is what a smoke run proves.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
set "MODE_ARG="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

set "SCRIPTS_DIR=%ROOT%\bin\examples\scripts"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

if /I "%~1"=="test" shift

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="-bc" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
call "%TOOLS_DIR%manage-standard-library.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

for %%F in ("%SCRIPTS_DIR%\*.swgs") do (
    rem The bare marker takes the default frame budget; the parser splits an '=' value off.
    call "%TOOLS_DIR%_shared-tooling.bat" :run_swc "%%~fF" --run-arg swag.smoke --run-arg swag.sandbox --build-cfg %BUILD_CFG%%EXTRA_ARGS%
    if not "!ERRORLEVEL!"=="0" exit /b !ERRORLEVEL!
)

exit /b 0
