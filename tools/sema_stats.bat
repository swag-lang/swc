@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"

swc_stats test --sema-only --no-test-native --no-test-jit --runtime -d "%ROOT%\bin\tests\sema" %*
if errorlevel 1 exit /b %errorlevel%
swc_stats test --no-output --no-test-native --runtime -d "%ROOT%\bin\tests\jit" %*
exit /b %errorlevel%
