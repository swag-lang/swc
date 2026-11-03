@echo off
setlocal DisableDelayedExpansion
set "mode=test"
set "compiler=%~dp0..\bin\swc.exe"
set "arguments=%*"
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
if /i "%~1"=="dm" (
    set "compiler=%~dp0..\bin\swc.dm.exe"
    set "compilerArgs=dm"
    for /f "tokens=1,2,*" %%A in ("%*") do (
        set "mode=%%B"
        set "arguments=%%C"
    )
) else if /i "%~1"=="accept" (
    set "mode=accept"
    for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
) else if /i "%~1"=="test" (
    set "mode=test"
    for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
)
if /i "%mode%"=="-h" goto usage
if /i "%mode%"=="--help" goto usage
if /i "%mode%"=="accept" goto accept
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
set "result=0"
call :testWorkspace std
call :testWorkspace examples
call :testWorkspace apps
call :testWorkspace reference
exit /b %result%

:testWorkspace
for /d %%M in ("%~dp0..\bin\%~1\modules\*") do call :testModule "%~1" "%%~fM"
exit /b 0

:testModule
rem An empty workspace is normal; the compiler rightly rejects an unmatched test filter.
rem Module tests live in *.swg; reference prose can also quote a golden tag.
findstr /s /m /r /c:"TestTag.*golden" "%~2\src\tests\cases\*.swg" >nul
if errorlevel 2 (
    set "result=1"
    exit /b 0
)
if errorlevel 1 exit /b 0
call "%~dp0%~1.bat" %compilerArgs% test "%~nx2" --test-tag golden %arguments%
if errorlevel 1 set "result=1"
exit /b 0

:usage
echo Usage: goldens.bat [dm] [test^|accept] [swc options]
exit /b 0

:accept
call "%~dp0_tool.bat" goldens accept
exit /b %errorlevel%
