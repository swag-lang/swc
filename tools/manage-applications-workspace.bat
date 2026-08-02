@echo off
setlocal

rem Builds, runs, or tests modules from the applications workspace.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
set "MODE_ARG="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

set "APPS_WORKSPACE=%ROOT%\bin\apps"
set "STD_OUTPUT_ROOT=%ROOT%\bin\std\.output"
set "SWC_COMMAND=build"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="
set "TEST_ARGS="
set "WORKSPACE_ARGS="

if /I "%~1"=="build" (
    shift
) else if /I "%~1"=="run" (
    set "SWC_COMMAND=run"
    shift
) else if /I "%~1"=="test" (
    set "SWC_COMMAND=test"
    rem Applications are native executables; run their tests once in the emitted artifact.
    rem An explicit --test-jit can still opt back into the in-process JIT pass.
    set "TEST_ARGS= --no-test-jit"
    shift
) else if /I "%~1"=="smoke" (
    set "SWC_COMMAND=smoke"
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
if /I "%~1"=="-bc" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--frames" (
    set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --frames %~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--run-timeout" (
    set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --run-timeout %~2"
    shift
    shift
    goto parse_args
)
if /I "%SWC_COMMAND%"=="test" if /I "%~1"=="--test-jit" (
    set "TEST_ARGS=%TEST_ARGS% --test-jit"
    shift
    goto parse_args
)
if /I "%SWC_COMMAND%"=="test" if /I "%~1"=="-tj" (
    set "TEST_ARGS=%TEST_ARGS% --test-jit"
    shift
    goto parse_args
)
if /I "%SWC_COMMAND%"=="test" if /I "%~1"=="--no-test-jit" (
    set "TEST_ARGS=%TEST_ARGS% --no-test-jit"
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
call "%TOOLS_DIR%manage-standard-library.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc %SWC_COMMAND% --workspace "%APPS_WORKSPACE%" --build-cfg %BUILD_CFG% --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%TEST_ARGS%%EXTRA_ARGS%
exit /b %ERRORLEVEL%
