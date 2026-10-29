@echo off
setlocal DisableDelayedExpansion
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
pushd "%~dp0..\vscode"
call npm.cmd ci
if errorlevel 1 goto failed
call npm.cmd test
if errorlevel 1 goto failed
if not exist images mkdir images
copy /y ..\bin\help\imgs\swag_icon.png images\swag_icon.png >nul
if errorlevel 1 goto failed
copy /y ..\bin\help\imgs\syntax.png images\syntax.png >nul
if errorlevel 1 goto failed
call npx.cmd vsce package
set "result=%ERRORLEVEL%"
popd
exit /b %result%
:failed
set "result=%ERRORLEVEL%"
popd
exit /b %result%
:usage
echo Usage: vsix.bat
exit /b 0
