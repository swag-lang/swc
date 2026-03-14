@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"

swc test --artifact-kind exe -d "%ROOT%\bin\tests" --out-dir "%EXE_OUTPUT%" --work-dir "%EXE_WORKDIR%" %*
exit /b %errorlevel%
