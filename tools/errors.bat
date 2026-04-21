@echo off
call "%~dp0test_module.bat" %* --bin-rel "tests\errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%~dp0test_module.bat" %* --bin-rel "tests\errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
exit /b 0
