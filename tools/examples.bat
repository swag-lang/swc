@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
set "MODE_ARG="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

set "EXAMPLES_WORKSPACE=%ROOT%\bin\examples"
set "STD_OUTPUT_ROOT=%ROOT%\bin\std\.output"
set "SWC_COMMAND=build"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="
set "WORKSPACE_ARGS="

if /I "%~1"=="build" (
    shift
) else if /I "%~1"=="run" (
    set "SWC_COMMAND=run"
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
if /I "%~1"=="--workspace-module" (
    set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="-m" (
    set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
call "%TOOLS_DIR%std.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%" || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc %SWC_COMMAND% --workspace "%EXAMPLES_WORKSPACE%" --build-cfg %BUILD_CFG% --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%EXTRA_ARGS%
exit /b %ERRORLEVEL%
