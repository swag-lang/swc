@echo off
setlocal

rem Builds or tests the executable language reference.
rem
rem     reference.bat [dm] [build|test] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "SWC_COMMAND=test"
call "%TOOLS_DIR%_args.bat" "build test" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help
if defined MODULE goto unexpected_name

set "REFERENCE_WORKSPACE=%ROOT%\bin\reference"
set "STD_OUTPUT_ROOT=%ROOT%\bin\std\.output"

rem Every reference page is a compiled source, so building one is testing it without running
rem the samples. The command stays 'test' either way; 'build' only stops short of executing.
set "REFERENCE_ARGS="
if /I "%SWC_COMMAND%"=="build" set "REFERENCE_ARGS= --no-test-jit --no-output"

call "%TOOLS_DIR%std.bat" %MODE_ARG% build -bc "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc test --workspace "%REFERENCE_WORKSPACE%" --build-cfg "%BUILD_CFG%" --import-api-dir "%STD_OUTPUT_ROOT%"%REFERENCE_ARGS%%EXTRA_ARGS%
exit /b %ERRORLEVEL%

:unexpected_name
echo The language reference is one workspace and takes no module name.
exit /b 1

:help
echo Builds or tests the executable language reference.
echo.
echo   reference.bat [dm] [build^|test] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   build              compile every page without running its samples
echo   test               compile and run them (default)
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
exit /b 0
