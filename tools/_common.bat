@echo off

if "%~1"=="" exit /b 1

set "__SWC_COMMON_LABEL=%~1"
shift
goto %__SWC_COMMON_LABEL%

:init
if "%~1"=="" exit /b 1
set "TOOLS_DIR=%~1"
for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"
set "SWC_BIN_DIR=%ROOT%\bin"
set "SWC_EXE=%SWC_BIN_DIR%\swc.exe"
set "SWAG_PATH=%SWC_BIN_DIR%"
if not defined TARGET_ARCH set "TARGET_ARCH=x86_64"
set "SWC_MODE=release"
if /I "%~2"=="dm" (
    set "SWC_EXE=%SWC_BIN_DIR%\swc_devmode.exe"
    set "SWC_MODE=devmode"
)
exit /b 0

:set_paths
if "%~3"=="" exit /b 1
set "WORKSPACE_NAME="
set "WORKSPACE_REL="
for /f "tokens=1* delims=\\" %%A in ("%~1") do (
    set "WORKSPACE_NAME=%%~A"
    set "WORKSPACE_REL=%%~B"
)
if not defined WORKSPACE_NAME exit /b 1
set "OUT_DIR=%ROOT%\bin\%WORKSPACE_NAME%\.output"
set "WORK_DIR=%ROOT%\bin\%WORKSPACE_NAME%\.tmp"
if defined WORKSPACE_REL (
    set "OUT_DIR=%OUT_DIR%\%WORKSPACE_REL%"
    set "WORK_DIR=%WORK_DIR%\%WORKSPACE_REL%"
)
set "OUT_DIR=%OUT_DIR%\%~2\%~3\%TARGET_ARCH%"
set "WORK_DIR=%WORK_DIR%\%~2\%~3\%TARGET_ARCH%"
exit /b 0
