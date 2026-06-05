@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"
set "MODE_ARG="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

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
if /I "%~1"=="--target-arch" (
    set "TARGET_ARCH=%~2"
    set "EXTRA_ARGS=%EXTRA_ARGS% --target-arch %~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
if /I "%SWC_MODE%"=="devmode" (
    call "%TOOLS_DIR%_common.bat" :run_swc unittest --dev-full%EXTRA_ARGS% || exit /b 1
)

call :run_source_test "tests\lexer" "Lexer" "lex-only" "--lex-only" || exit /b 1
call :run_source_test "tests\parser" "Parser" "syntax-only" "--syntax-only" || exit /b 1
call :run_source_test "tests\errors\lexer" "Lexer" "lex-only" "--lex-only" || exit /b 1
call :run_source_test "tests\errors\parser" "Parser" "syntax-only" "--syntax-only" || exit /b 1
call :run_source_test "tests\sema" "Sema" "sema-only" "--sema-only" || exit /b 1
call :run_source_test "tests\errors\sema" "Sema" "sema-only" "--sema-only" || exit /b 1
call :run_source_test "tests\jit" "Jit" "no-output" "--no-output" || exit /b 1
call :run_source_test "tests\safety" "Safety" "no-output" "--no-output" || exit /b 1
call :run_native_test "executable" || exit /b 1
call :run_api_export_preserve_test || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc run --workspace "%ROOT%\bin\tests\workspace" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0

:run_source_test
call "%TOOLS_DIR%_source_tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "%~1" --module-namespace "%~2" --artifact-label "%~3" --build-cfg "%BUILD_CFG%" %~4
exit /b %ERRORLEVEL%

:run_native_test
set "ARTIFACT_KIND=%~1"
call "%TOOLS_DIR%_common.bat" :set_paths "tests\native" "%ARTIFACT_KIND%" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

call "%TOOLS_DIR%_common.bat" :run_swc test --artifact-kind "%ARTIFACT_KIND%" -d "%ROOT%\bin\tests\native" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS%
exit /b %ERRORLEVEL%

:run_api_export_preserve_test
set "PRESERVE_WORKSPACE=%ROOT%\bin\tests\workspace_api_export_preserve"
set "PRESERVE_DIR=%PRESERVE_WORKSPACE%\.output\provider\shared-library\%BUILD_CFG%\%TARGET_ARCH%"
set "PRESERVE_FILE=%PRESERVE_DIR%\api-export-preserve.sentinel"

call "%TOOLS_DIR%_common.bat" :run_swc build --workspace "%PRESERVE_WORKSPACE%" --workspace-module provider --build-cfg "%BUILD_CFG%"%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if not exist "%PRESERVE_DIR%" exit /b 1

> "%PRESERVE_FILE%" echo keep
call "%TOOLS_DIR%_common.bat" :run_swc sema --workspace "%PRESERVE_WORKSPACE%" --workspace-module provider --build-cfg "%BUILD_CFG%" --rebuild%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" (
    del "%PRESERVE_FILE%" >nul 2>nul
    exit /b %ERRORLEVEL%
)

if not exist "%PRESERVE_FILE%" (
    echo API export removed a non-API artifact: "%PRESERVE_FILE%"
    exit /b 1
)

del "%PRESERVE_FILE%" >nul 2>nul
call "%TOOLS_DIR%_common.bat" :run_swc sema --workspace "%PRESERVE_WORKSPACE%" --workspace-module provider --build-cfg "%BUILD_CFG%" --rebuild%EXTRA_ARGS%
exit /b %ERRORLEVEL%
