@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_unittest_args.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"

call "%TOOLS_DIR%_common.bat" :run_swc run --workspace "%ROOT%\bin\unittests\workspace" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0
