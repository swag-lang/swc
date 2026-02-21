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

echo Unknown suite "%SUITE%". Expected "sema" or "syntax".
exit /b 2

:sema
%EXE% sema --verify --runtime -d "%ROOT%\bin\tests\sema" %EXTRA%
exit /b %errorlevel%

:syntax
%EXE% syntax --verify -d "%ROOT%\bin\tests\lexer" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax --verify -d "%ROOT%\bin\tests\parser" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\tests\legit" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\std\modules" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\runtime" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\reference" %EXTRA%
if errorlevel 1 exit /b %errorlevel%
%EXE% syntax -d "%ROOT%\bin\examples" %EXTRA%
exit /b %errorlevel%

:usage
echo Usage: _suite.bat ^<sema^|syntax^> ^<exe^> [extra args...]
exit /b 2
