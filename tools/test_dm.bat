@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "NATIVE_WORKDIR=%NATIVE_OUTPUT%\tmp"

swc_devmode test --backend-kind all -d "%ROOT%\bin\tests" --out-dir "%NATIVE_OUTPUT%" --work-dir "%NATIVE_WORKDIR%" %*
exit /b %errorlevel%
