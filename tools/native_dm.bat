@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "RUN_OUTPUT=%NATIVE_OUTPUT%\native-run"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"
set "RUN_WORKDIR=%NATIVE_OUTPUT%\work\native-run"

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
set "EXTRA_ARGS=!EXTRA_ARGS! %~1"
shift
goto parse_args

:run
if /I "!ARTIFACT_KIND!"=="run" (
    swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\!BUILD_CFG!" --work-dir "%RUN_WORKDIR%\!BUILD_CFG!" --build-cfg !BUILD_CFG! !EXTRA_ARGS!
    if errorlevel 1 exit /b 1
) else (
    swc_devmode test --artifact-kind !ARTIFACT_KIND! -d "%ROOT%\bin\tests\native" --out-dir "%NATIVE_OUTPUT%\!ARTIFACT_KIND!\!BUILD_CFG!" --work-dir "%NATIVE_OUTPUT%\work\!ARTIFACT_KIND!\!BUILD_CFG!" --build-cfg !BUILD_CFG! !EXTRA_ARGS!
    if errorlevel 1 exit /b 1
)

exit /b 0
