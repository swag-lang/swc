@echo off
setlocal

rem Builds, runs, tests, or smokes the examples workspace, whole or one module.
rem
rem     examples.bat [dm] [build|run|test|smoke] [<module>] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "SWC_COMMAND=build"
call "%TOOLS_DIR%_args.bat" "build run test smoke" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help

set "EXAMPLES_WORKSPACE=%ROOT%\bin\examples"
set "STD_OUTPUT_ROOT=%ROOT%\bin\std\.output"
if defined MODULE set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %MODULE%"

call "%TOOLS_DIR%std.bat" %MODE_ARG% build -bc "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc %SWC_COMMAND% --workspace "%EXAMPLES_WORKSPACE%" --build-cfg "%BUILD_CFG%" --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%RUN_ARGS%%EXTRA_ARGS%
exit /b %ERRORLEVEL%

:help
echo Builds, runs, tests, or smokes the examples workspace.
echo.
echo   examples.bat [dm] [build^|run^|test^|smoke] [^<module^>] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   ^<module^>           one of bin/examples/modules, for instance gui2 or pixel4
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo   --frames ^<count^>   bound a run or a smoke to that many frames
echo   --run-timeout ^<s^>  fail a run or a smoke that outlives that many seconds
echo.
echo   examples.bat run gui2        launch one example
echo   examples.bat dm test gui2    run its tests with the DevMode compiler
echo.
echo The standard library is built first. 'smoke' proves a program starts and keeps
echo going for a bounded number of frames, isolated from the machine.
exit /b 0
