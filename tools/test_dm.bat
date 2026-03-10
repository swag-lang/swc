@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"

swc_devmode test --backend-kind all -d "%ROOT%\bin\tests" %*
exit /b %errorlevel%
