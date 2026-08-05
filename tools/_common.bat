@echo off

rem Output-path and compiler-launch helpers for the repository tools.
rem
rem     call "%TOOLS_DIR%_common.bat" :<label> [arguments]

if "%~1"=="" exit /b 1

set "COMMON_LABEL=%~1"
shift
goto %COMMON_LABEL%

rem :set_paths <workspace-relative path> <artifact label> <build configuration>
rem Sets OUT_DIR and WORK_DIR for one artifact of one workspace.
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

rem :run_swc <arguments...>
rem Launches the selected compiler with every remaining argument.
:run_swc
if "%~1"=="" exit /b 1
set "SWC_RUN_ARGS="

:run_swc_collect
if "%~1"=="" goto run_swc_ready
set "SWC_RUN_ARGS=%SWC_RUN_ARGS% %1"
shift
goto run_swc_collect

:run_swc_ready
if defined SWC_RUN_ARGS set "SWC_RUN_ARGS=%SWC_RUN_ARGS:~1%"
"%SWC_EXE%" %SWC_RUN_ARGS%
set "SWC_RUN_ERROR=%ERRORLEVEL%"
set "SWC_RUN_ARGS="
exit /b %SWC_RUN_ERROR%
