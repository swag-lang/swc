@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

set "TEST_DIR_REL="
set "MODULE_LABEL="
set "MODULE_NAMESPACE="
set "BUILD_CFG=fast-debug"
set "ARTIFACT_LABEL=exe"
set "STAGE_ARGS="
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--test-dir-rel" (
    set "TEST_DIR_REL=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--module-label" (
    set "MODULE_LABEL=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--module-namespace" (
    set "MODULE_NAMESPACE=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--artifact-label" (
    set "ARTIFACT_LABEL=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--lex-only" (
    set "STAGE_ARGS=%STAGE_ARGS% --lex-only"
    shift
    goto parse_args
)
if /I "%~1"=="--syntax-only" (
    set "STAGE_ARGS=%STAGE_ARGS% --syntax-only"
    shift
    goto parse_args
)
if /I "%~1"=="--sema-only" (
    set "STAGE_ARGS=%STAGE_ARGS% --sema-only"
    shift
    goto parse_args
)
if /I "%~1"=="--no-output" (
    set "STAGE_ARGS=%STAGE_ARGS% --no-output"
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
if not defined TEST_DIR_REL exit /b 1
if not defined MODULE_LABEL exit /b 1
if not defined MODULE_NAMESPACE exit /b 1

call "%TOOLS_DIR%common.bat" :set_paths tests "%MODULE_LABEL%" "%ARTIFACT_LABEL%" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%

%SWC_EXE% test --artifact-kind exe -d "%ROOT%\%TEST_DIR_REL%" --module-namespace %MODULE_NAMESPACE% --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG%%STAGE_ARGS%%EXTRA_ARGS%
if errorlevel 1 exit /b %errorlevel%

exit /b 0
