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
set "WORKSPACE_MODULE="
set "APPLICATION_ARGS="

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
if /I "%SWC_COMMAND%"=="run" if /I "%~1"=="--run-arg" goto parse_application_arg
if /I "%~1"=="--workspace-module" (
    set "WORKSPACE_MODULE=%~2"
    set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="-m" (
    set "WORKSPACE_MODULE=%~2"
    set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:parse_application_arg
shift
if "%~1"=="" (
    echo --run-arg requires a value.
    exit /b 1
)
set "APPLICATION_ARG_VALUE=%~1"
shift

:parse_application_arg_suffix
if "%~1"=="" goto commit_application_arg
set "APPLICATION_ARG_SUFFIX=%~1"
if "%APPLICATION_ARG_SUFFIX:~0,1%"=="-" goto commit_application_arg
rem cmd.exe tokenizes '=' in batch arguments. Reassemble values such as name=value.
set "APPLICATION_ARG_VALUE=%APPLICATION_ARG_VALUE%=%APPLICATION_ARG_SUFFIX%"
shift
goto parse_application_arg_suffix

:commit_application_arg
set "APPLICATION_ARGS=%APPLICATION_ARGS% "%APPLICATION_ARG_VALUE%""
goto parse_args

:run
call "%TOOLS_DIR%manage-standard-library.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
if /I "%SWC_COMMAND%"=="run" goto run_application

call "%TOOLS_DIR%_shared-tooling.bat" :run_swc %SWC_COMMAND% --workspace "%APPS_WORKSPACE%" --build-cfg %BUILD_CFG% --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%TEST_ARGS%%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

if /I "%SWC_COMMAND%"=="build" (
    if not defined WORKSPACE_MODULE (
        call "%TOOLS_DIR%_package-application.bat" "%ROOT%" sCapture "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1
        call "%TOOLS_DIR%_package-application.bat" "%ROOT%" sCrypt "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1
    ) else (
        call "%TOOLS_DIR%_package-application.bat" "%ROOT%" "%WORKSPACE_MODULE%" "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1
    )
)

exit /b 0

:run_application
if not defined WORKSPACE_MODULE (
    echo Running an application requires --workspace-module ^<name^> or -m ^<name^>.
    exit /b 1
)

call "%TOOLS_DIR%_shared-tooling.bat" :run_swc build --workspace "%APPS_WORKSPACE%" --build-cfg %BUILD_CFG% --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

call "%TOOLS_DIR%_package-application.bat" "%ROOT%" "%WORKSPACE_MODULE%" "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1
set "APPLICATION_DIR=%APPS_WORKSPACE%\.output\%WORKSPACE_MODULE%\executable\%BUILD_CFG%\%TARGET_ARCH%"
set "APPLICATION_EXE=%APPLICATION_DIR%\%WORKSPACE_MODULE%.exe"

echo Launching %WORKSPACE_MODULE%...
pushd "%APPLICATION_DIR%" || exit /b 1
"%APPLICATION_EXE%"%APPLICATION_ARGS%
set "APPLICATION_ERROR=%ERRORLEVEL%"
popd
exit /b %APPLICATION_ERROR%
