@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "EXTRA_ARGS=%*"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "DLL_OUTPUT=%NATIVE_OUTPUT%\dll"
set "LIB_OUTPUT=%NATIVE_OUTPUT%\lib"
set "RUN_OUTPUT=%NATIVE_OUTPUT%\native-run"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"
set "DLL_WORKDIR=%NATIVE_OUTPUT%\work\dll"
set "LIB_WORKDIR=%NATIVE_OUTPUT%\work\lib"
set "RUN_WORKDIR=%NATIVE_OUTPUT%\work\native-run"

call :run_cfg release
if errorlevel 1 exit /b %errorlevel%
call :run_cfg debug
if errorlevel 1 exit /b %errorlevel%
call :run_cfg fast-debug
if errorlevel 1 exit /b %errorlevel%
call :run_cfg fast-compile
if errorlevel 1 exit /b %errorlevel%

exit /b 0

:run_cfg
set "BUILD_CFG=%~1"

for %%S in (lexer parser sema jit) do (
    set "STAGE_ARGS="
    if /I "%%S"=="lexer" set "STAGE_ARGS=--lex-only"
    if /I "%%S"=="parser" set "STAGE_ARGS=--syntax-only"
    if /I "%%S"=="sema" set "STAGE_ARGS=--sema-only"
    if /I "%%S"=="jit" set "STAGE_ARGS=--no-output"
    swc test -d "%ROOT%\bin\tests\%%S" --build-cfg !BUILD_CFG! !STAGE_ARGS! !EXTRA_ARGS!
    if errorlevel 1 exit /b 1
)

swc test --artifact-kind exe -d "%ROOT%\bin\tests\native" --out-dir "%EXE_OUTPUT%" --work-dir "%EXE_WORKDIR%" --build-cfg !BUILD_CFG! !EXTRA_ARGS!
if errorlevel 1 exit /b 1
swc run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\!BUILD_CFG!" --work-dir "%RUN_WORKDIR%\!BUILD_CFG!" --build-cfg !BUILD_CFG! !EXTRA_ARGS!
if errorlevel 1 exit /b 1
for %%K in (dll lib) do (
    swc test --artifact-kind %%K -d "%ROOT%\bin\tests\native" --out-dir "%NATIVE_OUTPUT%\%%K" --work-dir "%NATIVE_OUTPUT%\work\%%K" --build-cfg !BUILD_CFG! !EXTRA_ARGS!
    if errorlevel 1 exit /b 1
)

exit /b 0
