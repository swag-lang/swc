@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_unittest_args.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"

if /I "%SWC_MODE%"=="devmode" (
    call "%TOOLS_DIR%_common.bat" :run_swc unittest --dev-full%EXTRA_ARGS% || exit /b 1
)

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0
