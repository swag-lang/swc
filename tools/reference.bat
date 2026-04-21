@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

set "BIN_REL=reference\tests\language"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

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
call "%TOOLS_DIR%common.bat" :set_paths "%BIN_REL%" "executable" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%

%SWC_EXE% test -m "%ROOT%\bin\%BIN_REL%" --artifact-kind executable --module-namespace Language --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

exit /b 0
