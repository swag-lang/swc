@echo off

if "%~1"=="" exit /b 1

set "__SWC_COMMON_LABEL=%~1"
shift
goto %__SWC_COMMON_LABEL%

:init
if "%~1"=="" exit /b 1
set "TOOLS_DIR=%~1"
for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"
set "OUTPUT_ROOT=%ROOT%\bin\.output"
set "TMP_ROOT=%ROOT%\bin\.tmp"
set "SWC_EXE=swc"
set "SWC_MODE=release"
if /I "%~2"=="dm" (
    set "SWC_EXE=swc_devmode"
    set "SWC_MODE=devmode"
)
exit /b 0

:set_paths
if "%~3"=="" exit /b 1
set "OUT_DIR=%OUTPUT_ROOT%\%~1\%~2\%~3"
set "WORK_DIR=%TMP_ROOT%\%~1\%~2\%~3"
exit /b 0
