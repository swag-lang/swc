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

call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "release" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "release" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "release" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "release" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "release" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "release" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "release" --no-output || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "release" --no-output || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "executable" --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "run" --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "shared-library" --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "static-library" --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%std.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%core.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%export.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "release" || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "debug" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "debug" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "debug" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "debug" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "debug" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "debug" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "debug" --no-output || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "debug" --no-output || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "executable" --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "run" --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "shared-library" --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "static-library" --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%std.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%core.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%export.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "debug" || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "executable" --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "run" --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "shared-library" --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "static-library" --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%std.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%core.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%export.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-debug" || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-compile" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-compile" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-compile" --lex-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-compile" --syntax-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-compile" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-compile" --sema-only || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "fast-compile" --no-output || exit /b 1
call "%TOOLS_DIR%_test_module.bat" %MODE_ARG%%EXTRA_ARGS% --bin-rel "tests\safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "fast-compile" --no-output || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "executable" --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "run" --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "shared-library" --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%native.bat" %MODE_ARG%%EXTRA_ARGS% --artifact-kind "static-library" --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%std.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%core.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-compile" || exit /b 1
call "%TOOLS_DIR%export.bat" %MODE_ARG%%EXTRA_ARGS% --build-cfg "fast-compile" || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0



