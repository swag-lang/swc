@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"

swc_stats sema --test --runtime -d "%ROOT%\bin\tests\sema" %*
if errorlevel 1 exit /b %errorlevel%
swc_stats sema --test --runtime -d "%ROOT%\bin\tests\jit" %*
exit /b %errorlevel%
