@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "REFERENCE_OUTPUT=%NATIVE_OUTPUT%\reference\release"
set "REFERENCE_WORKDIR=%NATIVE_OUTPUT%\work\reference\release"

swc test -m "%ROOT%\bin\reference\tests\language" --artifact-kind exe --module-namespace Language --out-dir "%REFERENCE_OUTPUT%" --work-dir "%REFERENCE_WORKDIR%" %*
if errorlevel 1 exit /b 1

exit /b 0
