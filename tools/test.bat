@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"

for %%S in (lexer parser sema jit native) do (
    set "STAGE_ARGS="
    if /I "%%S"=="lexer" set "STAGE_ARGS=--lex-only"
    if /I "%%S"=="parser" set "STAGE_ARGS=--syntax-only"
    if /I "%%S"=="sema" set "STAGE_ARGS=--sema-only"
    if /I "%%S"=="jit" set "STAGE_ARGS=--no-output"
    swc test --artifact-kind exe -d "%ROOT%\bin\tests\%%S" --out-dir "%EXE_OUTPUT%" --work-dir "%EXE_WORKDIR%" !STAGE_ARGS! %*
    if errorlevel 1 exit /b 1
)

exit /b 0
