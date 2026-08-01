@echo off
setlocal

rem Runs native code generation, linking, and execution tests.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_parse-test-arguments.bat" "%TOOLS_DIR%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

set "ARTIFACT_KIND=executable"
call "%TOOLS_DIR%_shared-tooling.bat" :set_paths "unittests\native" "%ARTIFACT_KIND%" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

call "%TOOLS_DIR%_shared-tooling.bat" :run_swc test --artifact-kind "%ARTIFACT_KIND%" -d "%ROOT%\bin\unittests\native" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
