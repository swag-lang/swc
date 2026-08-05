@echo off
setlocal

rem Runs one standalone example script, or smokes every one of them.
rem
rem     scripts.bat [dm] [run|smoke] [<script>] [options...]
rem
rem A script declares no #test, so there is nothing for the test command to run. What is worth
rem proving about it is that it starts and keeps going, which is what a smoke run proves.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "SWC_COMMAND="
call "%TOOLS_DIR%_args.bat" "run smoke" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help

set "SCRIPTS_DIR=%ROOT%\bin\examples\scripts"

rem Naming a script means wanting to see it; naming none means proving they all still start.
if defined SWC_COMMAND goto resolve
set "SWC_COMMAND=smoke"
if defined MODULE set "SWC_COMMAND=run"

rem A name is resolved before anything is built, so a typo costs nothing.
:resolve
set "SCRIPT_FILE="
if not defined MODULE goto build_std
set "SCRIPT_FILE=%SCRIPTS_DIR%\%MODULE%"
if /I not "%MODULE:~-5%"==".swgs" set "SCRIPT_FILE=%SCRIPT_FILE%.swgs"
if not exist "%SCRIPT_FILE%" goto unknown_script

:build_std
call "%TOOLS_DIR%std.bat" %MODE_ARG% build -bc "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
if not defined SCRIPT_FILE goto smoke_all
call :run_one "%SCRIPT_FILE%"
exit /b %ERRORLEVEL%

:smoke_all
for %%F in ("%SCRIPTS_DIR%\*.swgs") do call :run_one "%%~fF" || exit /b 1
exit /b 0

:run_one
rem A script has no smoke command of its own: the markers are what bound and isolate the run.
rem The bare marker takes the default frame budget, and an explicit one always wins.
set "SMOKE_ARGS="
if /I not "%SWC_COMMAND%"=="smoke" goto run_one_launch
if "%RUN_ARG_NAMES%"=="%RUN_ARG_NAMES:swag.smoke=%" set "SMOKE_ARGS=%SMOKE_ARGS% --run-arg swag.smoke"
if "%RUN_ARG_NAMES%"=="%RUN_ARG_NAMES:swag.sandbox=%" set "SMOKE_ARGS=%SMOKE_ARGS% --run-arg swag.sandbox"

:run_one_launch
call "%TOOLS_DIR%_common.bat" :run_swc "%~1" --build-cfg "%BUILD_CFG%"%SMOKE_ARGS%%RUN_ARGS%%WORKSPACE_ARGS%%EXTRA_ARGS% || exit /b 1
exit /b 0

:unknown_script
echo Unknown script "%MODULE%". Available scripts:
for %%F in ("%SCRIPTS_DIR%\*.swgs") do echo   %%~nF
exit /b 1

:help
echo Runs one standalone example script, or smokes every one of them.
echo.
echo   scripts.bat [dm] [run^|smoke] [^<script^>] [options...]
echo.
echo   dm                          use the DevMode compiler
echo   ^<script^>                    a name from bin/examples/scripts, with or without .swgs
echo   -bc ^<config^>                release, debug, or fast-debug (default fast-debug)
echo   --run-arg swag.smoke=^<n^>    bound the run to that many frames
echo.
echo   scripts.bat snake            launch one script
echo   scripts.bat                  smoke every script
echo   scripts.bat smoke snake      smoke that one
echo.
echo Naming a script runs it; naming none smokes them all, isolated from the machine.
exit /b 0
