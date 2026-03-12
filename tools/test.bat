@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "DLL_OUTPUT=%NATIVE_OUTPUT%\dll"
set "LIB_OUTPUT=%NATIVE_OUTPUT%\lib"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"
set "DLL_WORKDIR=%NATIVE_OUTPUT%\work\dll"
set "LIB_WORKDIR=%NATIVE_OUTPUT%\work\lib"

swc run --test --backend-kind exe -d "%ROOT%\bin\tests" --out-dir "%EXE_OUTPUT%" --work-dir "%EXE_WORKDIR%" %*
if errorlevel 1 exit /b %errorlevel%
swc run --test --backend-kind dll -d "%ROOT%\bin\tests" --out-dir "%DLL_OUTPUT%" --work-dir "%DLL_WORKDIR%" %*
if errorlevel 1 exit /b %errorlevel%
swc run --test --backend-kind lib -d "%ROOT%\bin\tests" --out-dir "%LIB_OUTPUT%" --work-dir "%LIB_WORKDIR%" %*
exit /b %errorlevel%
