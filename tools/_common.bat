@echo off

if "%~1"=="" exit /b 1

set "__SWC_COMMON_LABEL=%~1"
shift
goto %__SWC_COMMON_LABEL%

:batch_begin
if "%~1"=="" exit /b 1
if not defined SWC_BATCH_UNITTEST_MARKER (
    set "SWC_BATCH_UNITTEST_MARKER=%TEMP%\swc_unittest_once_%RANDOM%_%RANDOM%_%RANDOM%.marker"
    if exist "%SWC_BATCH_UNITTEST_MARKER%" del /q "%SWC_BATCH_UNITTEST_MARKER%" >nul 2>nul
    set "SWC_BATCH_UNITTEST_MARKER_OWNER=%~f1"
)
exit /b 0

:batch_end
if "%~1"=="" exit /b 1
if /I "%SWC_BATCH_UNITTEST_MARKER_OWNER%"=="%~f1" (
    if defined SWC_BATCH_UNITTEST_MARKER if exist "%SWC_BATCH_UNITTEST_MARKER%" del /q "%SWC_BATCH_UNITTEST_MARKER%" >nul 2>nul
    set "SWC_BATCH_UNITTEST_MARKER="
    set "SWC_BATCH_UNITTEST_MARKER_OWNER="
)
exit /b 0

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

:run_swc
if "%~1"=="" exit /b 1
set "__SWC_RUN_ARGS="
:run_swc_collect
if "%~1"=="" goto run_swc_ready
set "__SWC_RUN_ARGS=%__SWC_RUN_ARGS% %1"
shift
goto run_swc_collect
:run_swc_ready
if defined __SWC_RUN_ARGS set "__SWC_RUN_ARGS=%__SWC_RUN_ARGS:~1%"
set "__SWC_RUN_DISABLE_UNITTEST="
echo %__SWC_RUN_ARGS% | findstr /C:"--no-unittest" >nul
if not errorlevel 1 set "__SWC_RUN_DISABLE_UNITTEST=1"
if defined SWC_BATCH_UNITTEST_MARKER if exist "%SWC_BATCH_UNITTEST_MARKER%" set "__SWC_RUN_ARGS=%__SWC_RUN_ARGS% --no-unittest"
"%SWC_EXE%" %__SWC_RUN_ARGS%
set "__SWC_RUN_ERROR=%ERRORLEVEL%"
if defined SWC_BATCH_UNITTEST_MARKER if not defined __SWC_RUN_DISABLE_UNITTEST if not exist "%SWC_BATCH_UNITTEST_MARKER%" >"%SWC_BATCH_UNITTEST_MARKER%" echo done
set "__SWC_RUN_ARGS="
set "__SWC_RUN_DISABLE_UNITTEST="
exit /b %__SWC_RUN_ERROR%
