@echo off
setlocal

rem Runs every compiler-focused unit and source-test suite.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

call "%TOOLS_DIR%test-cpp-units.bat" %* || exit /b 1
call "%TOOLS_DIR%test-lexer-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-parser-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-semantic-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-jit-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-safety-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-sanity-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-native-suite.bat" %* || exit /b 1
call "%TOOLS_DIR%test-workspace-suite.bat" %* || exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
