@echo off
setlocal

rem Builds every repository workspace.
rem
rem     build.bat [dm] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help
if defined MODULE goto unexpected_name

if defined ALL_CFG goto all_cfg
call :build_set "%BUILD_CFG%" || exit /b 1
exit /b 0

:all_cfg
for %%C in (release debug fast-debug) do call :build_set "%%C" || exit /b 1
exit /b 0

:build_set
set "CFG=%~1"
call "%TOOLS_DIR%std.bat" %MODE_ARG% build -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG% build -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%apps.bat" %MODE_ARG% build -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG% build -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc build --workspace "%ROOT%\bin\unittests\workspace" --build-cfg "%CFG%"%EXTRA_ARGS% || exit /b 1
exit /b 0

:unexpected_name
echo build.bat builds every workspace and takes no name. Use std.bat, examples.bat,
echo apps.bat, or reference.bat to build one workspace or one module.
exit /b 1

:help
echo Builds every repository workspace.
echo.
echo   build.bat [dm] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo   --all-cfg          repeat the whole build in all three configurations
echo.
echo Covers the standard library, the examples, the applications, the language
echo reference, and the multi-module workspace suite.
exit /b 0
