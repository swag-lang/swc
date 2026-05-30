@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"

set "MODE_ARG="
set "EXTRA_ARGS="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

:parse_args
if "%~1"=="" goto run
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
for %%C in (release debug fast-debug fast-compile) do (
    call "%TOOLS_DIR%tests.bat" %MODE_ARG% --build-cfg "%%C"%EXTRA_ARGS% || exit /b 1
)

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0
