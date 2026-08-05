@echo off
setlocal

rem Builds, runs, tests, or smokes the applications workspace, whole or one module.
rem
rem     apps.bat [dm] [build|run|test|smoke] [<module>] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
set "SWC_COMMAND=build"
call "%TOOLS_DIR%_args.bat" "build run test smoke" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help
if /I "%SWC_COMMAND%"=="run" if not defined MODULE goto missing_module

set "APPS_WORKSPACE=%ROOT%\bin\apps"
set "STD_OUTPUT_ROOT=%ROOT%\bin\std\.output"
if defined MODULE set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --workspace-module %MODULE%"

rem Applications are native executables; their tests run once in the emitted artifact.
rem An explicit --test-jit can still opt back into the in-process JIT pass.
set "TEST_ARGS="
if /I "%SWC_COMMAND%"=="test" set "TEST_ARGS= --no-test-jit"

call "%TOOLS_DIR%std.bat" %MODE_ARG% build -bc "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
if /I "%SWC_COMMAND%"=="run" goto run_application

call "%TOOLS_DIR%_common.bat" :run_swc %SWC_COMMAND% --workspace "%APPS_WORKSPACE%" --build-cfg "%BUILD_CFG%" --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%TEST_ARGS%%RUN_ARGS%%EXTRA_ARGS% || exit /b 1
if /I not "%SWC_COMMAND%"=="build" exit /b 0

rem A built application is only usable once its runtime files sit beside the executable.
if not defined MODULE goto package_all
call "%TOOLS_DIR%_package-app.bat" "%ROOT%" "%MODULE%" "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1
exit /b 0

:package_all
for /d %%D in ("%APPS_WORKSPACE%\modules\*") do call "%TOOLS_DIR%_package-app.bat" "%ROOT%" "%%~nxD" "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1
exit /b 0

rem 'run' launches the packaged executable itself, from its own directory, so it finds the
rem files that sit beside it. Everything given as --run-arg becomes an application argument.
:run_application
call "%TOOLS_DIR%_common.bat" :run_swc build --workspace "%APPS_WORKSPACE%" --build-cfg "%BUILD_CFG%" --import-api-dir "%STD_OUTPUT_ROOT%"%WORKSPACE_ARGS%%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_package-app.bat" "%ROOT%" "%MODULE%" "%BUILD_CFG%" "%TARGET_ARCH%" || exit /b 1

set "APPLICATION_DIR=%APPS_WORKSPACE%\.output\%MODULE%\executable\%BUILD_CFG%\%TARGET_ARCH%"
echo Launching %MODULE%...
pushd "%APPLICATION_DIR%" || exit /b 1
"%APPLICATION_DIR%\%MODULE%.exe"%APP_ARGS%
set "APPLICATION_ERROR=%ERRORLEVEL%"
popd
exit /b %APPLICATION_ERROR%

:missing_module
echo Running an application needs its name: apps.bat run ^<module^>
exit /b 1

:help
echo Builds, runs, tests, or smokes the applications workspace.
echo.
echo   apps.bat [dm] [build^|run^|test^|smoke] [^<module^>] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   ^<module^>           one of bin/apps/modules, for instance sCrypt or sCapture
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo   --frames ^<count^>   bound a smoke to that many frames
echo   --run-arg ^<value^>  an argument for the launched application
echo.
echo   apps.bat run sCrypt          launch one application
echo   apps.bat dm test sCapture    run its tests with the DevMode compiler
echo.
echo A build copies each application's runtime files beside its executable. 'run' needs
echo a module name and launches the packaged executable from its own directory.
exit /b 0
