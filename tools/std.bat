@echo off
setlocal

rem Builds or tests the standard library, whole or one module.
rem
rem     std.bat [dm] [build|test] [<module>] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "SWC_COMMAND=build"
call "%TOOLS_DIR%_args.bat" "build test" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help

set "STD_WORKSPACE=%ROOT%\bin\std"
set "STD_OUTPUT_ROOT=%STD_WORKSPACE%\.output"
if defined MODULE set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %MODULE%"

call "%TOOLS_DIR%_common.bat" :run_swc build --workspace "%STD_WORKSPACE%" --build-cfg "%BUILD_CFG%"%WORKSPACE_ARGS%%EXTRA_ARGS% || exit /b 1
if /I not "%SWC_COMMAND%"=="test" exit /b 0

rem A module is tested from its own module file, against the API the workspace build published.
for /d %%D in ("%STD_WORKSPACE%\modules\*") do call :test_module "%%~fD" || exit /b 1
exit /b 0

:test_module
set "MODULE_DIR=%~1"
for %%I in ("%MODULE_DIR%") do set "MODULE_NAME=%%~nxI"
if defined MODULE if /I not "%MODULE_NAME%"=="%MODULE%" exit /b 0

set "HAS_TESTS="
if exist "%MODULE_DIR%\src\unittests\*.test.swg" set "HAS_TESTS=1"
if exist "%MODULE_DIR%\src\tests\unittests\*.test.swg" set "HAS_TESTS=1"
if not defined HAS_TESTS exit /b 0

call "%TOOLS_DIR%_common.bat" :set_paths "std\%MODULE_NAME%" "executable" "%BUILD_CFG%" || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc test --artifact-kind executable --module-file "%MODULE_DIR%\module.swg" -d "src" --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg "%BUILD_CFG%" --import-api-dir "%STD_OUTPUT_ROOT%"%EXTRA_ARGS%%RUN_ARGS% || exit /b 1
exit /b 0

:help
echo Builds or tests the standard library.
echo.
echo   std.bat [dm] [build^|test] [^<module^>] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   ^<module^>           one of bin/std/modules, for instance core or pixel
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo   --run-arg ^<value^>  pass a run argument to the tested module
echo.
echo Testing always builds the workspace first. Modules without a unit test are skipped.
exit /b 0
