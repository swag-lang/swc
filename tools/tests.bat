@echo off
setlocal

rem Runs the repository test set: everything, or only what a working-tree change requires.
rem
rem     tests.bat [dm] [changed|plan] [<path>] [options...]
rem
rem Two intents, two commands. 'test' runs a module's #test functions and never its #main;
rem 'smoke' runs the real program for a bounded number of frames to prove it starts. Examples
rem declare no #test, so they are smoked: running 'test' on them would report zero tests and
rem pass without proving anything. Applications get both.
rem
rem The set is a ladder of five rungs, ordered by what each one costs against what it can see,
rem and every rung runs in every requested configuration before the next one starts. A defect
rem that only release can produce then reports in the first minute instead of after two complete
rem passes: the configuration is the inner loop, not the outer one.
rem
rem 'changed' asks tools/_scope.bat which surfaces the working tree touches and climbs the same
rem ladder carrying only their work. It never writes to a tracked file: the two commands that are
rem validated by regenerating their output, doc and format, are reported as steps to take.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "changed plan" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help
if defined MODULE if not defined SWC_COMMAND goto unexpected_name

set "SUITES=cpp lexer parser sema"
set "SUITES_CODEGEN=jit safety sanity native workspace"

set "CFG_LIST=%BUILD_CFG%"
if defined ALL_CFG set "CFG_LIST=release debug fast-debug"

if not defined SWC_COMMAND goto whole_set
call "%TOOLS_DIR%_scope.bat" %MODULE% || exit /b 1
call :measure
call :report
if /I "%SWC_COMMAND%"=="plan" exit /b 0
if "%SCOPE_COUNT%"=="0" exit /b 0
if defined SCOPE_ALL goto whole_set

call :for_cfg scoped_frontend || exit /b 1
call :for_cfg scoped_codegen || exit /b 1
call :for_cfg scoped_library || exit /b 1
call :for_cfg scoped_product || exit /b 1
call :for_cfg scoped_breadth || exit /b 1
exit /b 0

:whole_set
call :for_cfg whole_frontend || exit /b 1
call :for_cfg whole_codegen || exit /b 1
call :for_cfg whole_library || exit /b 1
call :for_cfg whole_product || exit /b 1
call :for_cfg whole_breadth || exit /b 1
exit /b 0

rem :for_cfg <rung label>
rem One rung, every configuration, before the next rung starts.
:for_cfg
for %%C in (%CFG_LIST%) do call :%~1 "%%C" || exit /b 1
exit /b 0

rem Rung 1. The frontend, and the compiler's own C++ suite: nothing here reaches a backend, and
rem between them they answer in seconds.
:whole_frontend
for %%S in (%SUITES%) do call "%TOOLS_DIR%unittests.bat" %MODE_ARG% %%S -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

rem Rung 2. Generated code, still on sources that stand alone. This is where a miscompile dies.
:whole_codegen
for %%S in (%SUITES_CODEGEN%) do call "%TOOLS_DIR%unittests.bat" %MODE_ARG% %%S -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

rem Rung 3. The standard library against its own assertions.
:whole_library
call "%TOOLS_DIR%std.bat" %MODE_ARG% test -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

rem Rung 4. What is shipped, and what documents the language.
:whole_product
call "%TOOLS_DIR%apps.bat" %MODE_ARG% test -bc "%~1"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%reference.bat" %MODE_ARG% test -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

rem Rung 5. Programs that only prove they start. Most of the campaign's time lives here, and none
rem of it can report anything an assertion above has not already had the chance to catch.
:whole_breadth
call "%TOOLS_DIR%scripts.bat" %MODE_ARG% smoke -bc "%~1"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%examples.bat" %MODE_ARG% smoke -bc "%~1"%EXTRA_ARGS% || exit /b 1
call "%TOOLS_DIR%apps.bat" %MODE_ARG% smoke -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

:scoped_frontend
for %%S in (%SUITES%) do if defined SCOPE_SUITE_%%S call "%TOOLS_DIR%unittests.bat" %MODE_ARG% %%S -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

:scoped_codegen
for %%S in (%SUITES_CODEGEN%) do if defined SCOPE_SUITE_%%S call "%TOOLS_DIR%unittests.bat" %MODE_ARG% %%S -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

rem A whole family goes through its workspace in one invocation, which checks that workspace once
rem instead of once per name. Naming them one at a time is only worth it below that.
:scoped_library
if "%SEL_STD%"=="0" exit /b 0
if "%SEL_STD%"=="%TOT_STD%" (
    call "%TOOLS_DIR%std.bat" %MODE_ARG% test -bc "%~1"%EXTRA_ARGS% || exit /b 1
    exit /b 0
)
for /d %%D in ("%ROOT%\bin\std\modules\*") do if defined SCOPE_STD_%%~nxD call "%TOOLS_DIR%std.bat" %MODE_ARG% test %%~nxD -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

:scoped_product
for /d %%D in ("%ROOT%\bin\apps\modules\*") do if defined SCOPE_APP_%%~nxD call "%TOOLS_DIR%apps.bat" %MODE_ARG% test %%~nxD -bc "%~1"%EXTRA_ARGS% || exit /b 1
if defined SCOPE_REFERENCE call "%TOOLS_DIR%reference.bat" %MODE_ARG% test -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

:scoped_breadth
call :scoped_scripts "%~1" || exit /b 1
call :scoped_examples "%~1" || exit /b 1
for /d %%D in ("%ROOT%\bin\apps\modules\*") do if defined SCOPE_APP_%%~nxD call "%TOOLS_DIR%apps.bat" %MODE_ARG% smoke %%~nxD -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

:scoped_scripts
if "%SEL_SCRIPTS%"=="0" exit /b 0
if "%SEL_SCRIPTS%"=="%TOT_SCRIPTS%" (
    call "%TOOLS_DIR%scripts.bat" %MODE_ARG% smoke -bc "%~1"%EXTRA_ARGS% || exit /b 1
    exit /b 0
)
for %%F in ("%ROOT%\bin\examples\scripts\*.swgs") do if defined SCOPE_SCRIPT_%%~nF call "%TOOLS_DIR%scripts.bat" %MODE_ARG% smoke %%~nF -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

:scoped_examples
if "%SEL_EXAMPLES%"=="0" exit /b 0
if "%SEL_EXAMPLES%"=="%TOT_EXAMPLES%" (
    call "%TOOLS_DIR%examples.bat" %MODE_ARG% smoke -bc "%~1"%EXTRA_ARGS% || exit /b 1
    exit /b 0
)
for /d %%D in ("%ROOT%\bin\examples\modules\*") do if defined SCOPE_EXAMPLE_%%~nxD call "%TOOLS_DIR%examples.bat" %MODE_ARG% smoke %%~nxD -bc "%~1"%EXTRA_ARGS% || exit /b 1
exit /b 0

rem How much of each family the selection holds, which both the report and the runner read.
:measure
call :count_dirs SCOPE_STD_ "%ROOT%\bin\std\modules" SEL_STD TOT_STD
call :count_dirs SCOPE_APP_ "%ROOT%\bin\apps\modules" SEL_APPS TOT_APPS
call :count_dirs SCOPE_EXAMPLE_ "%ROOT%\bin\examples\modules" SEL_EXAMPLES TOT_EXAMPLES
set "SEL_SCRIPTS=0"
set "TOT_SCRIPTS=0"
for %%F in ("%ROOT%\bin\examples\scripts\*.swgs") do call :count_one SCOPE_SCRIPT_%%~nF SEL_SCRIPTS TOT_SCRIPTS
exit /b 0

rem :count_dirs <variable prefix> <parent directory> <selected counter> <total counter>
:count_dirs
set "%~3=0"
set "%~4=0"
for /d %%D in ("%~2\*") do call :count_one %~1%%~nxD "%~3" "%~4"
exit /b 0

:count_one
set /a %~3+=1
if defined %~1 set /a %~2+=1
exit /b 0

:report
if "%SCOPE_COUNT%"=="0" (
    echo Nothing changed against HEAD, so there is nothing to run.
    exit /b 0
)
echo %SCOPE_COUNT% changed file^(s^) select:
set "REPORT_ANY="
if defined SCOPE_ALL goto report_all

set "REPORT="
for %%S in (%SUITES% %SUITES_CODEGEN%) do if defined SCOPE_SUITE_%%S call set "REPORT=%%REPORT%% %%S"
call :report_line "suites" "%REPORT%"
call :report_names SCOPE_STD_ "std" "%ROOT%\bin\std\modules" %SEL_STD% %TOT_STD%
call :report_names SCOPE_APP_ "apps" "%ROOT%\bin\apps\modules" %SEL_APPS% %TOT_APPS%
call :report_names SCOPE_EXAMPLE_ "examples" "%ROOT%\bin\examples\modules" %SEL_EXAMPLES% %TOT_EXAMPLES%
call :report_scripts
if defined SCOPE_REFERENCE call :report_line "reference" "the whole workspace"
goto report_notes

:report_all
call :report_line "everything" "in %CFG_LIST%"
if defined SCOPE_UNKNOWN call :report_line "because" "%SCOPE_UNKNOWN% matches no known surface"
goto report_notes

rem Both rewrite tracked files, so neither belongs inside a test command. They are named here
rem because the change that selected them is validated by reading what they produce.
:report_notes
if defined SCOPE_DOC call :report_line "also" "regenerate with tools/web.bat and read the diff"
if defined SCOPE_FORMAT call :report_line "also" "reformat with tools/format.bat and read the diff"
if defined SCOPE_WARN_PROJECT call :report_line "note" "%SCOPE_WARN_PROJECT% may carry a compile flag; run the whole set by hand if it does"
if not defined REPORT_ANY call :report_line "nothing" "no surface this campaign covers is affected"
echo.
exit /b 0

rem :report_line <label> <value>
rem The value arrives with the leading space its accumulator left, and an empty one prints nothing.
:report_line
set "REPORT_VALUE=%~2"
if not defined REPORT_VALUE exit /b 0
if "%REPORT_VALUE:~0,1%"==" " set "REPORT_VALUE=%REPORT_VALUE:~1%"
set "REPORT_LABEL=%~1          "
echo   %REPORT_LABEL:~0,10% %REPORT_VALUE%
set "REPORT_ANY=1"
exit /b 0

rem :report_names <variable prefix> <label> <parent directory> <selected> <total>
rem Naming a handful says more than counting them; naming twenty says less.
:report_names
if "%~4"=="0" exit /b 0
if %~4 GTR 6 (
    call :report_line "%~2" "%~4 of %~5"
    exit /b 0
)
set "REPORT="
for /d %%D in ("%~3\*") do if defined %~1%%~nxD call set "REPORT=%%REPORT%% %%~nxD"
call :report_line "%~2" "%REPORT%"
exit /b 0

:report_scripts
if "%SEL_SCRIPTS%"=="0" exit /b 0
if %SEL_SCRIPTS% GTR 6 (
    call :report_line "scripts" "%SEL_SCRIPTS% of %TOT_SCRIPTS%"
    exit /b 0
)
set "REPORT="
for %%F in ("%ROOT%\bin\examples\scripts\*.swgs") do if defined SCOPE_SCRIPT_%%~nF call set "REPORT=%%REPORT%% %%~nF"
call :report_line "scripts" "%REPORT%"
exit /b 0

:unexpected_name
echo tests.bat runs a whole set and takes no name. Use unittests.bat, std.bat, examples.bat,
echo apps.bat, reference.bat, or scripts.bat to reach one suite, module, or script.
exit /b 1

:help
echo Runs the repository test set, whole or scoped to what changed.
echo.
echo   tests.bat [dm] [changed^|plan] [^<path^>] [options...]
echo.
echo   dm                 use the DevMode compiler
echo   changed            run only what the working-tree change requires
echo   plan               print that selection, and run nothing
echo   ^<path^>             answer for that one file instead of the working tree,
echo                      which is how the map is asked before a change is made
echo   -bc ^<config^>       release, debug, or fast-debug (default fast-debug)
echo   --all-cfg          repeat the selected set in all three configurations
echo.
echo Five rungs, cheapest and most specific first: the frontend suites, the code
echo generation suites, the standard library, the applications and the reference,
echo then the programs that only prove they start. Each rung runs in every requested
echo configuration before the next one begins, so a fault only one configuration can
echo produce reports without waiting for the others to finish.
echo.
echo 'changed' maps each changed path to a surface, adds whatever imports a selected
echo standard library module, and climbs the same ladder carrying only that. A path
echo matching no surface selects everything, so an unmapped file costs time instead
echo of coverage.
exit /b 0
