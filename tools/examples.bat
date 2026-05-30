@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if /I "%~1"=="dm" shift

set "EXAMPLES_WORKSPACE=%ROOT%\bin\examples"
set "SWC_COMMAND=build"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

if /I "%~1"=="build" (
    shift
) else if /I "%~1"=="test" (
    set "SWC_COMMAND=test"
    shift
)

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
call "%TOOLS_DIR%_common.bat" :run_swc %SWC_COMMAND% --workspace "%EXAMPLES_WORKSPACE%" --build-cfg %BUILD_CFG%%EXTRA_ARGS%
exit /b %ERRORLEVEL%
