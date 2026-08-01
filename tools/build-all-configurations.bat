@echo off
setlocal

rem Builds every repository workspace in release, debug, and fast-debug.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

set "MODE_ARG="
set "EXTRA_ARGS="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

:parse_args
if "%~1"=="" goto run
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
for %%C in (release debug fast-debug) do (
    call :build_config "%%C" || exit /b 1
)

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0

:build_config
set "BUILD_CFG=%~1"
call "%TOOLS_DIR%manage-standard-library.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-examples-workspace.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-applications-workspace.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-reference-workspace.bat" %MODE_ARG% build --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc build --workspace "%ROOT%\bin\tests\workspace" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
exit /b 0
