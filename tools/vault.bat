@echo off
setlocal DisableDelayedExpansion
set "compiler=%~dp0..\bin\swc.exe"
set "dm="
set "arguments=%*"
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
if /i "%~1"=="dm" (
    set "dm=dm"
    set "compiler=%~dp0..\bin\swc.dm.exe"
    for /f "tokens=1,*" %%A in ("%*") do set "arguments=%%B"
)
if /i "%arguments%"=="-h" goto usage
if /i "%arguments%"=="--help" goto usage
if not exist "%compiler%" (
    echo error: compiler not found: "%compiler%"
    exit /b 1
)
set "workspace=%~dp0..\bin\apps"
set "appDir=%workspace%\.output\swagvault\executable\release\x86_64"
"%compiler%" build --workspace "%workspace%" --workspace-module swagvault --build-cfg release --tag vault.integration --num-cores 6 %arguments%
if errorlevel 1 exit /b %errorlevel%
copy /y "%workspace%\modules\swagvault\vendor\winfsp\runtime\winfsp-x64.dll" "%appDir%\winfsp-x64.dll" >nul
copy /y "%workspace%\modules\swagvault\vendor\winfsp\runtime\winfsp-x64.sys" "%appDir%\winfsp-x64.sys" >nul
if exist "%appDir%\integration-result.txt" del "%appDir%\integration-result.txt"
pushd "%appDir%"
swagvault.exe %arguments%
set "result=%ERRORLEVEL%"
if exist integration-result.txt type integration-result.txt
popd
call "%~dp0apps.bat" %dm% build swagvault -bc release
if errorlevel 1 if "%result%"=="0" set "result=1"
exit /b %result%
:usage
echo Usage: vault.bat [dm]
exit /b 0
