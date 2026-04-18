@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"
set "REFERENCE_OUTPUT=%NATIVE_OUTPUT%\reference\release"
set "REFERENCE_WORKDIR=%NATIVE_OUTPUT%\work\reference\release"

for %%S in (lexer parser errors\lexer errors\parser sema errors\sema jit safety native) do (
    set "STAGE_ARGS="
    set "MODULE_NAMESPACE="
    if /I "%%S"=="lexer" set "STAGE_ARGS=--lex-only"
    if /I "%%S"=="lexer" set "MODULE_NAMESPACE=Lexer"
    if /I "%%S"=="parser" set "STAGE_ARGS=--syntax-only"
    if /I "%%S"=="parser" set "MODULE_NAMESPACE=Parser"
    if /I "%%S"=="errors\lexer" set "STAGE_ARGS=--lex-only"
    if /I "%%S"=="errors\lexer" set "MODULE_NAMESPACE=Lexer"
    if /I "%%S"=="errors\parser" set "STAGE_ARGS=--syntax-only"
    if /I "%%S"=="errors\parser" set "MODULE_NAMESPACE=Parser"
    if /I "%%S"=="sema" set "STAGE_ARGS=--sema-only"
    if /I "%%S"=="sema" set "MODULE_NAMESPACE=Sema"
    if /I "%%S"=="errors\sema" set "STAGE_ARGS=--sema-only"
    if /I "%%S"=="errors\sema" set "MODULE_NAMESPACE=Sema"
    if /I "%%S"=="jit" set "STAGE_ARGS=--no-output"
    if /I "%%S"=="jit" set "MODULE_NAMESPACE=Jit"
    if /I "%%S"=="safety" set "STAGE_ARGS=--no-output"
    if /I "%%S"=="safety" set "MODULE_NAMESPACE=Safety"
    if /I "%%S"=="native" set "MODULE_NAMESPACE=Native"
    swc test --artifact-kind exe -d "%ROOT%\bin\tests\%%S" --module-namespace !MODULE_NAMESPACE! --out-dir "%EXE_OUTPUT%" --work-dir "%EXE_WORKDIR%" !STAGE_ARGS! %*
    if errorlevel 1 exit /b 1
)

swc test -m "%ROOT%\bin\reference\tests\language" --artifact-kind exe --module-namespace Language --out-dir "%REFERENCE_OUTPUT%" --work-dir "%REFERENCE_WORKDIR%" %*
if errorlevel 1 exit /b 1

exit /b 0
