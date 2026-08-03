@echo off
setlocal

rem Runs the multi-module workspace integration tests.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_parse-test-arguments.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

set "WORKSPACE=%ROOT%\bin\unittests\workspace"
set "WORKSPACE_RUN_LOG=%TEMP%\swag-workspace-run-%RANDOM%-%RANDOM%.log"

rem A test build writes a different executable to the normal output path. The following run
rem must invalidate that artifact and rebuild the executable containing the regular #main.
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc build --workspace "%WORKSPACE%" --workspace-module consumer_exe --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc test --workspace "%WORKSPACE%" --workspace-module consumer_exe --build-cfg "%BUILD_CFG%" --no-test-jit%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc run --workspace "%WORKSPACE%" --workspace-module consumer_exe --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% >"%WORKSPACE_RUN_LOG%" 2>&1
set "WORKSPACE_RUN_ERROR=%ERRORLEVEL%"
type "%WORKSPACE_RUN_LOG%"

if not "%WORKSPACE_RUN_ERROR%"=="0" goto workspace_run_done
findstr /L /C:"SWAG_WORKSPACE_MAIN_RAN" "%WORKSPACE_RUN_LOG%" >nul
set "WORKSPACE_RUN_ERROR=%ERRORLEVEL%"
if not "%WORKSPACE_RUN_ERROR%"=="0" echo Workspace run did not reach the normal entry point after a test build.

:workspace_run_done
del /Q "%WORKSPACE_RUN_LOG%" >nul 2>&1
if not "%WORKSPACE_RUN_ERROR%"=="0" exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
