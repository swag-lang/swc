@echo off
setlocal

rem Runs compiler, script, library, example, application, and reference tests once.
rem
rem Two intents, two commands. 'test' runs a module's #test functions and never its #main;
rem 'smoke' runs the real program for a bounded number of frames to prove it starts. Examples
rem declare no #test, so they are smoked: running 'test' on them would report zero tests and
rem pass without proving anything. Applications get both.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_shared-tooling.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
call "%TOOLS_DIR%_shared-tooling.bat" :batch_begin "%~f0"

set "MODE_ARG="
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="
if /I "%~1"=="dm" (
    set "MODE_ARG=dm"
    shift
)

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="-bc" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
call "%TOOLS_DIR%test-compiler-suites.bat" %MODE_ARG% --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%test-example-scripts.bat" %MODE_ARG% test --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-standard-library.bat" %MODE_ARG% test --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-examples-workspace.bat" %MODE_ARG% smoke --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-applications-workspace.bat" %MODE_ARG% test --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-applications-workspace.bat" %MODE_ARG% smoke --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%manage-reference-workspace.bat" %MODE_ARG% test --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1

call "%TOOLS_DIR%_shared-tooling.bat" :batch_end "%~f0"
exit /b 0
