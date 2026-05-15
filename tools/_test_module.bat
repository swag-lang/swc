@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if /I "%~1"=="dm" shift

set "BIN_REL="
set "MODULE_NAMESPACE="
set "BUILD_CFG=fast-debug"
set "ARTIFACT_LABEL=executable"
set "STAGE_ARGS="
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--bin-rel" (
    set "BIN_REL=%~2"
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
if /I "%~1"=="--target-arch" (
    set "TARGET_ARCH=%~2"
    set "EXTRA_ARGS=%EXTRA_ARGS% --target-arch %~2"
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
if not defined BIN_REL exit /b 1
if not defined MODULE_NAMESPACE exit /b 1

call "%TOOLS_DIR%_common.bat" :set_paths "%BIN_REL%" "%ARTIFACT_LABEL%" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

"%SWC_EXE%" test --artifact-kind executable -d "%ROOT%\bin\%BIN_REL%" --module-namespace %MODULE_NAMESPACE% --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG%%STAGE_ARGS%%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

exit /b 0
