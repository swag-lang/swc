@echo off
setlocal

rem Runs the compiler test suites: one named suite, or every one of them in order.
rem
rem     unittests.bat [dm] [<suite>] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "" %*
if errorlevel 1 exit /b 1

set "SUITES=cpp lexer parser sema jit safety sanity native workspace"
if defined WANT_HELP goto help

if not defined MODULE goto run_all
set "IS_SUITE="
for %%S in (%SUITES%) do if /I "%%S"=="%MODULE%" set "IS_SUITE=1"
if not defined IS_SUITE goto unknown_suite
call :suite_%MODULE% || exit /b 1
exit /b 0

:run_all
for %%S in (%SUITES%) do call :suite_%%S || exit /b 1
exit /b 0

rem The compiler's own C++ tests are linked into the DevMode build only.
:suite_cpp
if /I not "%SWC_MODE%"=="devmode" exit /b 0
call "%TOOLS_DIR%_common.bat" :run_swc unittest --dev-full%EXTRA_ARGS% || exit /b 1
exit /b 0

:suite_lexer
call :source_suite "unittests\lexer" Lexer lex-only --lex-only || exit /b 1
call :source_suite "unittests\errors\lexer" Lexer lex-only --lex-only || exit /b 1
exit /b 0

:suite_parser
call :source_suite "unittests\parser" Parser syntax-only --syntax-only || exit /b 1
call :source_suite "unittests\errors\parser" Parser syntax-only --syntax-only || exit /b 1
exit /b 0

:suite_sema
call :source_suite "unittests\sema" Sema sema-only --sema-only || exit /b 1
call :source_suite "unittests\errors\sema" Sema sema-only --sema-only || exit /b 1
exit /b 0

:suite_jit
call :source_suite "unittests\jit" Jit no-output --no-output || exit /b 1
exit /b 0

:suite_safety
call :source_suite "unittests\safety" Safety no-output --no-output || exit /b 1
exit /b 0

:suite_sanity
call :source_suite "unittests\sanity" Sanity no-output --no-output || exit /b 1
exit /b 0

rem Native runs the whole pipeline, so it emits and executes a real artifact.
:suite_native
call :source_suite "unittests\native" Native executable || exit /b 1
exit /b 0

:suite_workspace
set "WORKSPACE=%ROOT%\bin\unittests\workspace"
set "RUN_LOG=%TEMP%\swag-workspace-run-%RANDOM%-%RANDOM%.log"

rem A test build writes a different executable to the normal output path. The following run
rem must invalidate that artifact and rebuild the executable containing the regular #main.
call "%TOOLS_DIR%_common.bat" :run_swc build --workspace "%WORKSPACE%" --workspace-module consumer_exe --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc test --workspace "%WORKSPACE%" --workspace-module consumer_exe --build-cfg "%BUILD_CFG%" --no-test-jit%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc run --workspace "%WORKSPACE%" --workspace-module consumer_exe --build-cfg "%BUILD_CFG%"%EXTRA_ARGS% >"%RUN_LOG%" 2>&1
set "RUN_ERROR=%ERRORLEVEL%"
type "%RUN_LOG%"

if not "%RUN_ERROR%"=="0" goto workspace_done
findstr /L /C:"SWAG_WORKSPACE_MAIN_RAN" "%RUN_LOG%" >nul
set "RUN_ERROR=%ERRORLEVEL%"
if not "%RUN_ERROR%"=="0" echo Workspace run did not reach the normal entry point after a test build.

:workspace_done
del /Q "%RUN_LOG%" >nul 2>&1
if not "%RUN_ERROR%"=="0" exit /b 1
exit /b 0

rem :source_suite <bin-relative directory> <module namespace> <artifact label> [<stage flag>]
:source_suite
set "SUITE_BIN_REL=%~1"
set "SUITE_NAMESPACE=%~2"
set "SUITE_LABEL=%~3"
set "SUITE_STAGE=%~4"
if defined SUITE_STAGE set "SUITE_STAGE= %SUITE_STAGE%"
call "%TOOLS_DIR%_common.bat" :set_paths "%SUITE_BIN_REL%" "%SUITE_LABEL%" "%BUILD_CFG%" || exit /b 1
call "%TOOLS_DIR%_common.bat" :run_swc test --artifact-kind executable -d "%ROOT%\bin\%SUITE_BIN_REL%" --module-namespace %SUITE_NAMESPACE% --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg "%BUILD_CFG%"%SUITE_STAGE%%EXTRA_ARGS% || exit /b 1
exit /b 0

:unknown_suite
echo Unknown suite "%MODULE%". Available suites: %SUITES%
exit /b 1

:help
echo Runs the compiler test suites.
echo.
echo   unittests.bat [dm] [^<suite^>] [options...]
echo.
echo   dm                 use the DevMode compiler, and run the C++ suite
echo   ^<suite^>            %SUITES%
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo.
echo Without a suite every suite runs, in the order above. Any other option is
echo forwarded to the compiler, for instance --seed, --num-cores, or --randomize.
exit /b 0
