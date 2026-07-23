@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_unittest_args.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"

call "%TOOLS_DIR%_source_tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "unittests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "%BUILD_CFG%" --sema-only || exit /b 1
call "%TOOLS_DIR%_source_tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "unittests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "%BUILD_CFG%" --sema-only || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0
