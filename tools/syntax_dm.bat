@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"

swc_devmode syntax --verify -d "%ROOT%\bin\tests\lexer" %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode syntax --verify -d "%ROOT%\bin\tests\parser" %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode syntax -d "%ROOT%\bin\std\modules" %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode syntax -d "%ROOT%\bin\reference" %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode syntax -d "%ROOT%\bin\examples" %*
exit /b %errorlevel%
