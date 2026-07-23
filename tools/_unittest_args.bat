@echo off

if "%~1"=="" exit /b 1
set "TOOLS_DIR=%~1"
shift

call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

set "MODE_ARG="
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

:parse_args
if "%~1"=="" exit /b 0
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
if /I "%~1"=="--target-arch" (
    set "TARGET_ARCH=%~2"
    set "EXTRA_ARGS=%EXTRA_ARGS% --target-arch %~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args
