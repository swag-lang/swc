@echo off
setlocal

rem Regenerates the website brand assets and all generated documentation pages.
rem
rem     web.bat [dm] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help

set "WEB_DIR=%ROOT%\web"
set "WEB_TOOLS_DIR=%WEB_DIR%\tools"
if not exist "%WEB_DIR%" mkdir "%WEB_DIR%" || exit /b 1

rem Generated files are opened with truncation and replaced in place. Keeping the current site
rem until each replacement succeeds avoids leaving an empty documentation tree after a failure.

rem The brand assets come first: the pages link them, and cutting them again here is what keeps
rem the mark, the icons and the favicons in step with their definition. The generator writes
rem relative to the repository root, so it runs from there whatever the caller's own directory.
pushd "%ROOT%" || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc "%WEB_TOOLS_DIR%\brand.swgs"%EXTRA_ARGS%
set "BRAND_ERROR=%ERRORLEVEL%"
popd
if not "%BRAND_ERROR%"=="0" exit /b %BRAND_ERROR%

call "%TOOLS_DIR%_common.bat" :run_swc doc --workspace "%ROOT%\bin\std" --doc-output-dir "%WEB_DIR%" --rebuild%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc doc --workspace "%ROOT%\bin\reference" --doc-output-dir "%WEB_DIR%" --rebuild%EXTRA_ARGS% || exit /b 1
exit /b 0

:help
echo Regenerates the brand assets and the complete website under web/.
echo.
echo   web.bat [dm] [options...]
echo.
echo Cuts the mark, the icons and the favicons first, then documents the bin/std and
echo bin/reference workspaces.
exit /b 0
