@echo off
setlocal DisableDelayedExpansion
set "compiler=%~dp0..\bin\swc.exe"
set "dm="
set "suite=%~1"
for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
if /i "%suite%"=="dm" (
    set "dm=dm"
    set "compiler=%~dp0..\bin\swc.dm.exe"
    for /f "tokens=1,*" %%A in ("%arguments%") do (
        set "suite=%%A"
        set "arguments=%%B"
    )
)
if /i "%suite%"=="dm" set "suite="
if "%suite:~0,1%"=="-" (
    if /i "%suite%"=="-h" goto usage
    if /i "%suite%"=="--help" goto usage
    set "arguments=%suite% %arguments%"
    set "suite="
)
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
if not defined suite goto all
if /i "%suite%"=="cpp" goto cpp
if /i "%suite%"=="lexer" goto pairedSource
if /i "%suite%"=="parser" goto pairedSource
if /i "%suite%"=="sema" goto pairedSource
if /i "%suite%"=="jit" call :source jit Jit executable --no-output %arguments%
if /i "%suite%"=="safety" call :source safety Safety executable --no-output --tag Swag.AllocatorSafety %arguments%
if /i "%suite%"=="sanity" call :source sanity Sanity executable --no-output %arguments%
if /i "%suite%"=="native" call :source native Native executable %arguments%
if /i "%suite%"=="workspace" goto workspace
if /i not "%suite%"=="jit" if /i not "%suite%"=="safety" if /i not "%suite%"=="sanity" if /i not "%suite%"=="native" if /i not "%suite%"=="workspace" (
    echo error: unknown compiler suite "%suite%"
    echo suites: cpp lexer parser sema jit safety sanity native workspace
    exit /b 1
)
exit /b %errorlevel%

:all
if /i "%compiler%"=="%~dp0..\bin\swc.dm.exe" (
    call "%~f0" dm cpp %arguments%
    if errorlevel 1 exit /b 1
)
for %%S in (lexer parser sema jit safety sanity native workspace) do (
    call "%~f0" %dm% %%S %arguments%
    if errorlevel 1 exit /b 1
)
exit /b 0
:usage
echo Usage: unittests.bat [dm] [suite] [swc options]
echo Suites: cpp lexer parser sema jit safety sanity native workspace
exit /b 0

:cpp
if not defined dm exit /b 0
call :readOptions %arguments%
if errorlevel 1 exit /b 1
"%compiler%" unittest --dev-full --num-cores 3 %cppArguments%
exit /b %errorlevel%

:pairedSource
if /i "%suite%"=="lexer" set "namespace=Lexer"
if /i "%suite%"=="lexer" set "stage=--lex-only"
if /i "%suite%"=="parser" set "namespace=Parser"
if /i "%suite%"=="parser" set "stage=--syntax-only"
if /i "%suite%"=="sema" set "namespace=Sema"
if /i "%suite%"=="sema" set "stage=--sema-only"
call :source %suite% %namespace% executable %stage% %arguments%
if errorlevel 1 exit /b %errorlevel%
call :source errors\%suite% %namespace% executable %stage% %arguments%
exit /b %errorlevel%

:readOptions
set "buildCfg=devmode"
set "numCores=3"
set "cppArguments="
:readOption
if "%~1"=="" exit /b 0
set "option=%~1"
if /i "%option%"=="-bc" goto readBuildCfg
if /i "%option%"=="--build-cfg" goto readBuildCfg
if /i "%option:~0,12%"=="--build-cfg=" (
    set "buildCfg=%option:~12%"
    shift
    goto readOption
)
if /i "%option%"=="-j" set "numCores=%~2"
if /i "%option%"=="--num-cores" set "numCores=%~2"
if /i "%option:~0,12%"=="--num-cores=" set "numCores=%option:~12%"
set "cppArguments=%cppArguments% %1"
shift
goto readOption

:readBuildCfg
if "%~2"=="" (
    echo error: option '%~1' needs a build configuration
    exit /b 1
)
set "buildCfg=%~2"
shift
shift
goto readOption

:source
set "folder=%~1"
set "namespace=%~2"
set "kind=%~3"
set "stage=%~4"
set "sourceArguments="
for /f "tokens=1,2,3,4,*" %%A in ("%*") do set "sourceArguments=%%E"
"%compiler%" test -d "%~dp0..\bin\unittests\%folder%" --module-namespace "%namespace%" --artifact-kind "%kind%" --num-cores 3 %stage% %sourceArguments%
exit /b %errorlevel%

:workspace
call :readOptions %arguments%
if errorlevel 1 exit /b 1
set "dynamicLibrary=%~dp0..\bin\unittests\workspace\.output\runtime_context_dynamic_dll\shared-library\%buildCfg%\x86_64\runtime_context_dynamic_dll.dll"
for %%I in ("%dynamicLibrary%") do set "dynamicLibrary=%%~fI"
rem The consumer loads this fixture by path, so no import can build it on demand.
"%compiler%" build --workspace "%~dp0..\bin\unittests\workspace" --workspace-module runtime_context_dynamic_dll --build-cfg "%buildCfg%" --num-cores "%numCores%"
if errorlevel 1 exit /b %errorlevel%
for /d %%M in ("%~dp0..\bin\unittests\workspace\modules\*") do (
    call :workspaceModule "%%~nxM"
    if errorlevel 1 exit /b 1
)

set "scriptOutput=%TEMP%\swc-workspace-script-%RANDOM%-%RANDOM%.txt"
"%compiler%" --build-cfg "%buildCfg%" --num-cores "%numCores%" "%~dp0..\bin\unittests\workspace\import_core_without_using.swgs" > "%scriptOutput%"
if errorlevel 1 (
    type "%scriptOutput%"
    del /q "%scriptOutput%"
    exit /b 1
)
findstr /c:"SWAG_IMPORTED_CORE_WITHOUT_USING_RAN" "%scriptOutput%" >nul
if errorlevel 1 (
    type "%scriptOutput%"
    del /q "%scriptOutput%"
    exit /b 1
)
type "%scriptOutput%"
del /q "%scriptOutput%"
exit /b 0

:workspaceModule
set "module=%~1"
if /i "%module%"=="sandbox_consumer" (
    "%compiler%" test --workspace "%~dp0..\bin\unittests\workspace" --workspace-module "%module%" --rebuild --no-test-native --num-cores 3 %arguments%
) else if /i "%module%"=="runtime_context_dynamic_consumer" (
    "%compiler%" test --workspace "%~dp0..\bin\unittests\workspace" --workspace-module "%module%" --no-test-jit --num-cores 3 "--run-arg=--dynamic-runtime-library=%dynamicLibrary%" %arguments%
) else (
    "%compiler%" test --workspace "%~dp0..\bin\unittests\workspace" --workspace-module "%module%" --no-test-jit --num-cores 3 %arguments%
)
exit /b %errorlevel%
