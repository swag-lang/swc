@echo off
call "%~dp0test_module.bat" %* --bin-rel "tests\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%~dp0native.bat" %* --artifact-kind "executable" --build-cfg "fast-debug" || exit /b 1
call "%~dp0reference.bat" %* --build-cfg "fast-debug" || exit /b 1
exit /b 0
