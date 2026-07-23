@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"

call "%TOOLS_DIR%cpp.bat" %* || exit /b 1
call "%TOOLS_DIR%lexer.bat" %* || exit /b 1
call "%TOOLS_DIR%parser.bat" %* || exit /b 1
call "%TOOLS_DIR%sema.bat" %* || exit /b 1
call "%TOOLS_DIR%jit.bat" %* || exit /b 1
call "%TOOLS_DIR%safety.bat" %* || exit /b 1
call "%TOOLS_DIR%sanity.bat" %* || exit /b 1
call "%TOOLS_DIR%native.bat" %* || exit /b 1
call "%TOOLS_DIR%workspace.bat" %* || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0
