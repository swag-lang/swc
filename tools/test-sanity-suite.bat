@echo off
setlocal

rem Runs static and lifecycle sanity tests.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_parse-test-arguments.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

call "%TOOLS_DIR%_run-source-tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "unittests\sanity" --module-namespace "Sanity" --artifact-label "no-output" --build-cfg "%BUILD_CFG%" --no-output || exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
