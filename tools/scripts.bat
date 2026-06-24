@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
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
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
call "%TOOLS_DIR%std.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

REM The scripts are independent compilation units; run them concurrently (each
REM swc invocation only partly saturates the cores) and fail if any fails.
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%_parallel.ps1" -Kind scripts -SwcExe "%SWC_EXE%" -Root "%ROOT%" -BuildCfg "%BUILD_CFG%" -ExtraArgs "%EXTRA_ARGS%" || exit /b 1

exit /b 0
