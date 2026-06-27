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

set "REFERENCE_WORKSPACE=%ROOT%\bin\reference"
set "STD_OUTPUT_ROOT=%ROOT%\bin\std\.output"
set "SWC_COMMAND=test"
set "REFERENCE_ARGS="
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

if /I "%~1"=="build" (
    set "REFERENCE_ARGS= --no-test-jit --no-output"
    shift
) else if /I "%~1"=="test" (
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
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
call "%TOOLS_DIR%std.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc %SWC_COMMAND% --workspace "%REFERENCE_WORKSPACE%" --build-cfg %BUILD_CFG% --import-api-dir "%STD_OUTPUT_ROOT%"%REFERENCE_ARGS%%EXTRA_ARGS%
exit /b %ERRORLEVEL%
