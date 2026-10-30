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
call :testWorkspace std
if errorlevel 1 exit /b 1
call :testWorkspace examples
if errorlevel 1 exit /b 1
call :testWorkspace apps
if errorlevel 1 exit /b 1
call :testWorkspace reference
exit /b %errorlevel%

:testWorkspace
rem An empty workspace is normal; the compiler rightly rejects an unmatched test filter.
rem Module tests live in *.test.swg; reference prose can also quote a golden tag.
findstr /s /m /r /c:"TestTag.*golden" "%~dp0..\bin\%~1\modules\*.test.swg" >nul
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
call "%~dp0%~1.bat" %compilerArgs% test --test-tag golden %arguments%
exit /b %errorlevel%

:usage
echo Usage: goldens.bat [dm] [test^|accept] [swc options]
exit /b 0

:accept
set "accepted=0"
for /r "%~dp0..\bin" %%F in (*.actual.txt *.actual.png) do (
    call :promote "%%~fF"
    if errorlevel 1 exit /b 1
)
if "%accepted%"=="0" echo no pending snapshot to accept
exit /b 0

:promote
set "actual=%~1"
set "golden=%actual:.actual.txt=.txt%"
set "golden=%golden:.actual.png=.png%"
move /y "%actual%" "%golden%" >nul
if errorlevel 1 exit /b 1
set /a accepted+=1
echo accepted %~nx1
exit /b 0
