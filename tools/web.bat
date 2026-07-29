@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_common.bat" :batch_begin "%~f0"

set "EXTRA_ARGS="
if /I "%~1"=="dm" (
    shift
)

:parse_args
if "%~1"=="" goto generate
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:generate
set "WEB_DIR=%ROOT%\web"
if not exist "%WEB_DIR%" mkdir "%WEB_DIR%" || exit /b 1

if exist "%WEB_DIR%\*.html" (
    del /Q "%WEB_DIR%\*.html"
    if errorlevel 1 exit /b 1
)
if exist "%WEB_DIR%\*.php" (
    del /Q "%WEB_DIR%\*.php"
    if errorlevel 1 exit /b 1
)
if exist "%WEB_DIR%\.htaccess" (
    del /Q "%WEB_DIR%\.htaccess"
    if errorlevel 1 exit /b 1
)
if exist "%WEB_DIR%\common" (
    rmdir /S /Q "%WEB_DIR%\common"
    if errorlevel 1 exit /b 1
)
if exist "%WEB_DIR%\html" (
    rmdir /S /Q "%WEB_DIR%\html"
    if errorlevel 1 exit /b 1
)

call "%TOOLS_DIR%_common.bat" :run_swc doc --workspace "%ROOT%\bin\std" --doc-output-dir "%WEB_DIR%" --rebuild%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc doc --workspace "%ROOT%\bin\reference" --doc-output-dir "%WEB_DIR%" --rebuild%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_common.bat" :batch_end "%~f0"
exit /b 0
