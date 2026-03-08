@echo off
setlocal

if "%~1"=="" goto :usage
if "%~2"=="" goto :usage

for %%I in ("%~dp0..") do set "ROOT=%%~fI"

set "SUITE=%~1"
set "EXE=%~2"
set "EXTRA=%3 %4 %5 %6 %7 %8 %9"

if /I "%SUITE%"=="sema" goto :sema
if /I "%SUITE%"=="syntax" goto :syntax
if /I "%SUITE%"=="test" goto :test

echo Unknown suite "%SUITE%". Expected "sema", "syntax", or "test".
exit /b 2

:sema
%EXE% sema --verify --runtime -d "%ROOT%\bin\tests\sema" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% sema --verify --runtime -d "%ROOT%\bin\tests\jit" %EXTRA%
exit /b %errorlevel%

:syntax
%EXE% syntax --verify -d "%ROOT%\bin\tests\lexer" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax --verify -d "%ROOT%\bin\tests\parser" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\std\modules" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\reference" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\examples" %EXTRA%
exit /b %errorlevel%

:test
%EXE% test --no-runtime --no-verify --backend-kind exe --num-cores 2 -d "%ROOT%\bin\tests\test" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% test --no-runtime --no-verify --backend-kind dll --num-cores 2 -d "%ROOT%\bin\tests\test" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% test --no-runtime --no-verify --backend-kind lib --num-cores 2 -d "%ROOT%\bin\tests\test" %EXTRA%
exit /b %errorlevel%

:usage
echo Usage: _suite.bat ^<sema^|syntax^|test^> ^<exe^> [extra args...]
exit /b 2
