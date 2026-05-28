@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if /I "%~1"=="dm" shift

set "STD_WORKSPACE=%ROOT%\bin\std"
set "STD_OUTPUT_ROOT=%STD_WORKSPACE%\.output"
set "SWC_COMMAND=build"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

if /I "%~1"=="build" (
    shift
) else if /I "%~1"=="test" (
    set "SWC_COMMAND=test"
    shift
)

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
if /I "%SWC_COMMAND%"=="test" goto run_test

call "%TOOLS_DIR%_common.bat" :run_swc %SWC_COMMAND% --workspace "%STD_WORKSPACE%" --build-cfg %BUILD_CFG%%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

exit /b 0

:run_test
call "%TOOLS_DIR%_common.bat" :run_swc build --workspace "%STD_WORKSPACE%" --build-cfg %BUILD_CFG%%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

for /d %%D in ("%STD_WORKSPACE%\modules\*") do (
    if exist "%%~fD\src\tests\*.test.swg" (
        set "MODULE_NAME=%%~nxD"
        set "MODULE_FILE=%%~fD\module.swg"

        call "%TOOLS_DIR%_common.bat" :set_paths "std\!MODULE_NAME!" "executable" "%BUILD_CFG%"
        if not "!ERRORLEVEL!"=="0" exit /b !ERRORLEVEL!

        call "%TOOLS_DIR%_common.bat" :run_swc test --artifact-kind executable --module-file "!MODULE_FILE!" -d "src" --out-dir "!OUT_DIR!" --work-dir "!WORK_DIR!" --build-cfg %BUILD_CFG% --import-api-dir "%STD_OUTPUT_ROOT%"%EXTRA_ARGS%
        if not "!ERRORLEVEL!"=="0" exit /b !ERRORLEVEL!
    )
)

exit /b 0
