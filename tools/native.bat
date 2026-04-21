@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

set "BIN_REL=tests\native"
set "BUILD_CFG=fast-debug"
set "ARTIFACT_KIND=executable"
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
if /I "%ARTIFACT_KIND%"=="run" goto run_artifact
goto test_artifact

:run_artifact
call "%TOOLS_DIR%common.bat" :set_paths "%BIN_REL%" "run" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%
%SWC_EXE% run -d "%ROOT%\bin\%BIN_REL%" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1
goto done

:test_artifact
call "%TOOLS_DIR%common.bat" :set_paths "%BIN_REL%" "%ARTIFACT_KIND%" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%
%SWC_EXE% test --artifact-kind %ARTIFACT_KIND% -d "%ROOT%\bin\%BIN_REL%" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

:done

exit /b 0
