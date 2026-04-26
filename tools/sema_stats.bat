@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "SWC_STATS_EXE=%ROOT%\.output\swc_stats.exe"

"%SWC_STATS_EXE%" test --sema-only --no-test-native --no-test-jit --runtime --module-namespace Sema -d "%ROOT%\bin\tests\sema" %*
if errorlevel 1 exit /b %errorlevel%
"%SWC_STATS_EXE%" test --no-output --no-test-native --runtime --module-namespace Jit -d "%ROOT%\bin\tests\jit" %*
exit /b %errorlevel%
