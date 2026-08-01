@echo off
setlocal

rem Regenerates the website brand assets and all generated documentation pages.
for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"
set "WEB_TOOLS_DIR=%ROOT%\web\tools"

call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

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

REM The brand assets come first: the pages link them, and cutting them again here is what
REM keeps the mark, the icons and the favicons in step with their definition. The generator
REM writes relative to the repository root, so it is run from there whatever the caller's
REM own directory.
pushd "%ROOT%" || exit /b 1
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc "%WEB_TOOLS_DIR%\brand.swgs"%EXTRA_ARGS%
set "BRAND_ERROR=%ERRORLEVEL%"
popd
if not "%BRAND_ERROR%"=="0" exit /b %BRAND_ERROR%

call "%TOOLS_DIR%_shared-tooling.bat" :run_swc doc --workspace "%ROOT%\bin\std" --doc-output-dir "%WEB_DIR%" --rebuild%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_shared-tooling.bat" :run_swc doc --workspace "%ROOT%\bin\reference" --doc-output-dir "%WEB_DIR%" --rebuild%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
