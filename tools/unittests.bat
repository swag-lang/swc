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

call :run_source_test "unittests\lexer" "Lexer" "lex-only" "--lex-only" || exit /b 1
call :run_source_test "unittests\parser" "Parser" "syntax-only" "--syntax-only" || exit /b 1
call :run_source_test "unittests\errors\lexer" "Lexer" "lex-only" "--lex-only" || exit /b 1
call :run_source_test "unittests\errors\parser" "Parser" "syntax-only" "--syntax-only" || exit /b 1
call :run_source_test "unittests\sema" "Sema" "sema-only" "--sema-only" || exit /b 1
call :run_source_test "unittests\errors\sema" "Sema" "sema-only" "--sema-only" || exit /b 1
call :run_source_test "unittests\jit" "Jit" "no-output" "--no-output" || exit /b 1
call :run_source_test "unittests\safety" "Safety" "no-output" "--no-output" || exit /b 1
call :run_native_test "executable" || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc run --workspace "%ROOT%\bin\unittests\workspace" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0

:run_source_test
call "%TOOLS_DIR%_source_tests.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "%~1" --module-namespace "%~2" --artifact-label "%~3" --build-cfg "%BUILD_CFG%" %~4
exit /b %ERRORLEVEL%

:run_native_test
set "ARTIFACT_KIND=%~1"
call "%TOOLS_DIR%_common.bat" :set_paths "unittests\native" "%ARTIFACT_KIND%" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

call "%TOOLS_DIR%_common.bat" :run_swc test --artifact-kind "%ARTIFACT_KIND%" -d "%ROOT%\bin\unittests\native" --module-namespace Native --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg "%BUILD_CFG%"%EXTRA_ARGS%
exit /b %ERRORLEVEL%
