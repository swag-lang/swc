@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

set "BUILD_CFG=fast-debug"
set "ARTIFACT_KIND=exe"
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift & shift
    goto parse_args
)
if /I "%~1"=="--artifact-kind" (
    set "ARTIFACT_KIND=%~2"
    shift & shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
if /I "%ARTIFACT_KIND%"=="run" (
    call "%TOOLS_DIR%common.bat" :set_paths tests "native" "run" "%BUILD_CFG%"
    if errorlevel 1 exit /b %errorlevel%
    %SWC_EXE% run -d "%ROOT%\bin\tests\native" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG%%EXTRA_ARGS%
    if errorlevel 1 exit /b 1
) else (
    call "%TOOLS_DIR%common.bat" :set_paths tests "native" "%ARTIFACT_KIND%" "%BUILD_CFG%"
    if errorlevel 1 exit /b %errorlevel%
    %SWC_EXE% test --artifact-kind %ARTIFACT_KIND% -d "%ROOT%\bin\tests\native" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG%%EXTRA_ARGS%
    if errorlevel 1 exit /b 1
)

exit /b 0
