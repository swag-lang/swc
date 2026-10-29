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
if /i "%suite%"=="cpp" (
    if /i not "%compiler%"=="%~dp0..\bin\swc.dm.exe" exit /b 0
    "%compiler%" unittest --dev-full --num-cores 6 %arguments%
    exit /b %errorlevel%
)
if /i "%suite%"=="lexer" (
    call :source lexer Lexer executable --lex-only %arguments%
    if errorlevel 1 exit /b %errorlevel%
    call :source errors\lexer Lexer executable --lex-only %arguments%
    exit /b %errorlevel%
)
if /i "%suite%"=="parser" (
    call :source parser Parser executable --syntax-only %arguments%
    if errorlevel 1 exit /b %errorlevel%
    call :source errors\parser Parser executable --syntax-only %arguments%
    exit /b %errorlevel%
)
if /i "%suite%"=="sema" (
    call :source sema Sema executable --sema-only %arguments%
    if errorlevel 1 exit /b %errorlevel%
    call :source errors\sema Sema executable --sema-only %arguments%
    exit /b %errorlevel%
)
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

:source
set "folder=%~1"
set "namespace=%~2"
set "kind=%~3"
set "stage=%~4"
set "sourceArguments="
for /f "tokens=1,2,3,4,*" %%A in ("%*") do set "sourceArguments=%%E"
"%compiler%" test -d "%~dp0..\bin\unittests\%folder%" --module-namespace "%namespace%" --artifact-kind "%kind%" --num-cores 6 %stage% %sourceArguments%
exit /b %errorlevel%

:workspace
set "buildCfg=devmode"
echo(%arguments%| findstr /i /c:"-bc release" /c:"--build-cfg release" /c:"--build-cfg=release" >nul && set "buildCfg=release"
set "dynamicLibrary=%~dp0..\bin\unittests\workspace\.output\runtime_context_dynamic_dll\shared-library\%buildCfg%\x86_64\runtime_context_dynamic_dll.dll"
for %%I in ("%dynamicLibrary%") do set "dynamicLibrary=%%~fI"
"%compiler%" test --workspace "%~dp0..\bin\unittests\workspace" --no-test-jit --num-cores 6 "--run-arg=--dynamic-runtime-library=%dynamicLibrary%" %arguments%
if errorlevel 1 exit /b %errorlevel%

set "scriptOutput=%TEMP%\swc-workspace-script-%RANDOM%-%RANDOM%.txt"
"%compiler%" --build-cfg "%buildCfg%" --num-cores 6 "%~dp0..\bin\unittests\workspace\import_core_without_using.swgs" > "%scriptOutput%"
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
