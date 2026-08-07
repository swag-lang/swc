@echo off

rem Resolves which part of the campaign a working-tree change actually requires.
rem
rem     call "%TOOLS_DIR%_scope.bat" [<path>...]
rem
rem The caller sets ROOT first. No setlocal: every SCOPE_* result is read by the caller.
rem Without a path the working tree answers the question; with one, that path does, which is how
rem the map is asked what a change would cost before making it.
rem
rem A path maps to a surface, a surface maps to work, and the work of every changed path is
rem unioned. A path that matches no surface selects the whole campaign: an unknown file has to
rem cost more than it saves, or the map silently stops covering the repository as it grows.
rem
rem Membership is one variable per name (SCOPE_STD_core, SCOPE_EXAMPLE_gui2) rather than a list,
rem so nothing has to search a string, and the caller enumerates the real directories against it.

if not defined ROOT exit /b 1

for /f "delims==" %%V in ('set SCOPE_ 2^>nul') do set "%%V="

set "SCOPE_ALL="
set "SCOPE_DOC="
set "SCOPE_FORMAT="
set "SCOPE_REFERENCE="
set "SCOPE_HAS_STD="
set "SCOPE_COUNT=0"
set "SCOPE_UNKNOWN="
set "SCOPE_WARN_PROJECT="

if not "%~1"=="" goto classify_arguments

rem 'diff HEAD' covers the staged and the unstaged half at once; untracked files are the other
rem half of a working tree, and a brand new test file is exactly the one that must not be missed.
for /f "usebackq delims=" %%F in (`git -C "%ROOT%" diff --name-only HEAD 2^>nul`) do call :classify "%%F"
for /f "usebackq delims=" %%F in (`git -C "%ROOT%" ls-files --others --exclude-standard 2^>nul`) do call :classify "%%F"
goto classify_done

:classify_arguments
if "%~1"=="" goto classify_done
call :classify "%~1"
shift
goto classify_arguments

:classify_done

rem SCOPE_ALL is the whole campaign, which the caller already knows how to run: leaving the
rem narrower results empty is what keeps 'everything' one code path instead of a wider union.
if "%SCOPE_COUNT%"=="0" exit /b 0
if defined SCOPE_ALL exit /b 0

rem Nothing consumes an example, a script or an application, so the graph is only worth walking
rem when a standard library module is in the selection.
if not defined SCOPE_HAS_STD exit /b 0
call :close_std_modules
call :close_consumers
exit /b 0

rem :classify <repository-relative path>
:classify
set "SCOPE_PATH=%~1"
if not defined SCOPE_PATH exit /b 0
set "SCOPE_PATH=%SCOPE_PATH:\=/%"
set /a SCOPE_COUNT+=1

rem The two commands that sit beside the compiler rather than inside it. Neither is on the path
rem that compiles a program, so neither can break one, and both are validated by regenerating
rem their output and reading the diff.
if /I "%SCOPE_PATH:~0,8%"=="src/Doc/" (set "SCOPE_DOC=1" & exit /b 0)
if /I "%SCOPE_PATH:~0,28%"=="src/Main/Command/Command.Doc" (set "SCOPE_DOC=1" & exit /b 0)
if /I "%SCOPE_PATH:~0,11%"=="src/Format/" (set "SCOPE_FORMAT=1" & set "SCOPE_SUITE_cpp=1" & exit /b 0)
if /I "%SCOPE_PATH:~0,31%"=="src/Main/Command/Command.Format" (set "SCOPE_FORMAT=1" & set "SCOPE_SUITE_cpp=1" & exit /b 0)
if /I "%SCOPE_PATH:~0,20%"=="src/Unittest/Format/" (set "SCOPE_FORMAT=1" & set "SCOPE_SUITE_cpp=1" & exit /b 0)

rem A C++ test cannot change what the compiler does.
if /I "%SCOPE_PATH:~0,13%"=="src/Unittest/" (set "SCOPE_SUITE_cpp=1" & exit /b 0)

rem A formatting configuration changes how sources are written, never what they mean.
if /I "%SCOPE_PATH:~-12%"==".swc-format/" (set "SCOPE_FORMAT=1" & exit /b 0)
if /I "%SCOPE_PATH:~-11%"==".swc-format" (set "SCOPE_FORMAT=1" & exit /b 0)

rem Emitting the image and its debug information is the one compiler area a JIT-only suite cannot
rem see and a smoke run cannot say anything useful about: what proves it is a real link, which the
rem native suite, the applications and the reference all perform.
if /I "%SCOPE_PATH:~0,19%"=="src/Backend/Linker/" goto surface_link
if /I "%SCOPE_PATH:~0,18%"=="src/Backend/Debug/" goto surface_link

rem Sema, code generation, the micro backend, the JIT, the runtime support and the driver all sit
rem under every compiled program. Nothing narrower than the whole campaign is honest there.
if /I "%SCOPE_PATH:~0,4%"=="src/" (set "SCOPE_ALL=1" & exit /b 0)

rem The prelude is analyzed by every invocation, so it is under everything too.
if /I "%SCOPE_PATH:~0,12%"=="bin/runtime/" (set "SCOPE_ALL=1" & exit /b 0)

if /I "%SCOPE_PATH:~0,16%"=="bin/std/modules/" (set "SCOPE_HAS_STD=1" & call :mark_at 16 SCOPE_STD_ / & exit /b 0)
if /I "%SCOPE_PATH:~0,21%"=="bin/examples/modules/" (call :mark_at 21 SCOPE_EXAMPLE_ / & exit /b 0)
if /I "%SCOPE_PATH:~0,21%"=="bin/examples/scripts/" (call :mark_at 21 SCOPE_SCRIPT_ . & exit /b 0)
if /I "%SCOPE_PATH:~0,17%"=="bin/apps/modules/" (call :mark_at 17 SCOPE_APP_ / & exit /b 0)
if /I "%SCOPE_PATH:~0,24%"=="bin/unittests/workspace/" (set "SCOPE_SUITE_workspace=1" & exit /b 0)
if /I "%SCOPE_PATH:~0,21%"=="bin/unittests/errors/" (call :mark_at 21 SCOPE_SUITE_ / & exit /b 0)
if /I "%SCOPE_PATH:~0,14%"=="bin/unittests/" (call :mark_at 14 SCOPE_SUITE_ / & exit /b 0)
if /I "%SCOPE_PATH:~0,14%"=="bin/reference/" (set "SCOPE_REFERENCE=1" & exit /b 0)

rem Nothing here is compiled into anything the campaign runs.
if /I "%SCOPE_PATH:~0,6%"=="tools/" exit /b 0
if /I "%SCOPE_PATH:~0,8%"==".agents/" exit /b 0
if /I "%SCOPE_PATH:~0,8%"=="backlog/" exit /b 0
if /I "%SCOPE_PATH:~0,8%"==".vscode/" exit /b 0
if /I "%SCOPE_PATH:~0,6%"=="bench/" exit /b 0

rem The generated site and the sources that cut it are the doc surface.
if /I "%SCOPE_PATH:~0,4%"=="web/" (set "SCOPE_DOC=1" & exit /b 0)

rem A repository document explains the work; it never changes what the work does.
if /I "%SCOPE_PATH:~-3%"==".md" exit /b 0

rem A project file almost always changes because a source file was added or removed, and those
rem sources classify themselves. It can also carry a compile flag, which nothing here can tell
rem apart, so the caller is told rather than the whole campaign being charged for the common case.
if /I "%SCOPE_PATH:~-4%"==".sln" (set "SCOPE_WARN_PROJECT=%SCOPE_PATH%" & exit /b 0)
if /I "%SCOPE_PATH:~-8%"==".filters" (set "SCOPE_WARN_PROJECT=%SCOPE_PATH%" & exit /b 0)
if /I "%SCOPE_PATH:~-8%"==".vcxproj" (set "SCOPE_WARN_PROJECT=%SCOPE_PATH%" & exit /b 0)

set "SCOPE_ALL=1"
if not defined SCOPE_UNKNOWN set "SCOPE_UNKNOWN=%SCOPE_PATH%"
exit /b 0

rem The suites that stop at the JIT never emit an image, so they cannot see this change at all.
:surface_link
set "SCOPE_SUITE_native=1"
set "SCOPE_SUITE_workspace=1"
set "SCOPE_REFERENCE=1"
for /d %%D in ("%ROOT%\bin\apps\modules\*") do set "SCOPE_APP_%%~nxD=1"
exit /b 0

rem :mark_at <prefix length> <variable prefix> <name delimiter>
rem Marks the name that follows the surface prefix. Scripts are named by their first dot segment,
rem so 'calc.symbols.swg' selects 'calc'; every other surface is named by its directory.
:mark_at
call set "SCOPE_REST=%%SCOPE_PATH:~%~1%%"
if not defined SCOPE_REST exit /b 0
for /f "tokens=1 delims=%~3" %%A in ("%SCOPE_REST%") do set "%~2%%A=1"
exit /b 0

rem A standard library module that imports a selected one is selected too. The graph is declared
rem by the '#import' lines of each module.swg, so nothing here is a hand-kept table. Four passes
rem reach a fixed point on a graph whose longest chain is win32 - core - pixel - gui.
:close_std_modules
for /l %%P in (1,1,4) do for /d %%D in ("%ROOT%\bin\std\modules\*") do call :select_if_imports "%%~fD\module.swg" "SCOPE_STD_%%~nxD"
exit /b 0

rem Whatever consumes a selected standard library module has to be exercised against it: an
rem example, an application, a script, and the reference, which imports core.
:close_consumers
for /d %%D in ("%ROOT%\bin\examples\modules\*") do call :select_if_imports "%%~fD\module.swg" "SCOPE_EXAMPLE_%%~nxD"
for /d %%D in ("%ROOT%\bin\apps\modules\*") do call :select_if_imports "%%~fD\module.swg" "SCOPE_APP_%%~nxD"
for %%F in ("%ROOT%\bin\examples\scripts\*.swgs") do call :select_if_imports "%%~fF" "SCOPE_SCRIPT_%%~nF"
if defined SCOPE_STD_core set "SCOPE_REFERENCE=1"
exit /b 0

rem :select_if_imports <source file> <variable to set>
rem An import reads '#import("name")' or '#import("name", location: "...")', and the line is
rem indented whenever it sits inside a conditional block, so the name is read rather than matched.
:select_if_imports
if defined %~2 exit /b 0
for /f "usebackq tokens=2 delims=()" %%I in (`findstr /L /C:"#import(" "%~1" 2^>nul`) do (set "SCOPE_IMPORT=%%I" & call :select_if_std "%~2")
exit /b 0

:select_if_std
set "SCOPE_IMPORT=%SCOPE_IMPORT:"=%"
for /f "tokens=1 delims=," %%A in ("%SCOPE_IMPORT%") do if defined SCOPE_STD_%%A set "%~1=1"
exit /b 0
