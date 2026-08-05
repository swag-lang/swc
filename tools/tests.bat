@echo off
setlocal

rem Runs the complete repository test set: compiler suites, scripts, standard library,
rem examples, applications, and the language reference.
rem
rem     tests.bat [dm] [options...]
rem
rem Two intents, two commands. 'test' runs a module's #test functions and never its #main;
rem 'smoke' runs the real program for a bounded number of frames to prove it starts. Examples
rem declare no #test, so they are smoked: running 'test' on them would report zero tests and
rem pass without proving anything. Applications get both.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help
if defined MODULE goto unexpected_name

if defined ALL_CFG goto all_cfg
call :run_set "%BUILD_CFG%" || exit /b 1
exit /b 0

:all_cfg
for %%C in (release debug fast-debug) do call :run_set "%%C" || exit /b 1
exit /b 0

:run_set
set "CFG=%~1"
call "%TOOLS_DIR%unittests.bat" %MODE_ARG% -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%scripts.bat" %MODE_ARG% smoke -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%std.bat" %MODE_ARG% test -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG% smoke -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%apps.bat" %MODE_ARG% test -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%apps.bat" %MODE_ARG% smoke -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG% test -bc "%CFG%"%EXTRA_ARGS% || exit /b 1
exit /b 0

:unexpected_name
echo tests.bat runs everything and takes no name. Use unittests.bat, std.bat, examples.bat,
echo apps.bat, reference.bat, or scripts.bat to reach one suite, module, or script.
exit /b 1

:help
echo Runs the complete repository test set.
echo.
echo   tests.bat [dm] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo   --all-cfg          repeat the whole set in all three configurations
echo.
echo Covers the compiler suites, the example scripts, the standard library, the
echo examples, the applications, and the language reference.
exit /b 0
