@echo off
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\lexer" --module-label "lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\parser" --module-label "parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\errors\lexer" --module-label "errors\lexer" --module-namespace "Lexer" --artifact-label "lex-only" --build-cfg "fast-debug" --lex-only || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\errors\parser" --module-label "errors\parser" --module-namespace "Parser" --artifact-label "syntax-only" --build-cfg "fast-debug" --syntax-only || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\sema" --module-label "sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\errors\sema" --module-label "errors\sema" --module-namespace "Sema" --artifact-label "sema-only" --build-cfg "fast-debug" --sema-only || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\jit" --module-label "jit" --module-namespace "Jit" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%~dp0test_module.bat" %* --test-dir-rel "bin\tests\safety" --module-label "safety" --module-namespace "Safety" --artifact-label "no-output" --build-cfg "fast-debug" --no-output || exit /b 1
call "%~dp0native.bat" %* --artifact-kind "exe" --build-cfg "fast-debug" || exit /b 1
call "%~dp0reference.bat" %* --build-cfg "fast-debug" || exit /b 1
exit /b 0
