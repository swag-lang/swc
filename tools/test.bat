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
if /I "%SWC_MODE%"=="devmode" (
    call "%TOOLS_DIR%_common.bat" :run_swc unittest --dev-full%EXTRA_ARGS% || exit /b 1
)

call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%TOOLS_DIR%export.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "executable" --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%std.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%core.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0

