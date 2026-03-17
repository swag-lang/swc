@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"

for %%S in (lexer parser sema jit native) do (
    swc test --artifact-kind exe -d "%ROOT%\bin\tests\%%S" --out-dir "%EXE_OUTPUT%" --work-dir "%EXE_WORKDIR%" %*
    if errorlevel 1 exit /b 1
)

exit /b 0
