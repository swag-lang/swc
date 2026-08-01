@echo off
setlocal

rem Runs semantic-analysis source tests and their expected diagnostics.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_parse-test-arguments.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

call "%TOOLS_DIR%_run-source-tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "unittests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "%BUILD_CFG%" --sema-only || exit /b 1
call "%TOOLS_DIR%_run-source-tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "unittests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "%BUILD_CFG%" --sema-only || exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
