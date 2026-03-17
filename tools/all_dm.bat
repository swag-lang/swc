@echo off
setlocal

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "NATIVE_OUTPUT=%ROOT%\.output"
set "EXE_OUTPUT=%NATIVE_OUTPUT%\exe"
set "DLL_OUTPUT=%NATIVE_OUTPUT%\dll"
set "LIB_OUTPUT=%NATIVE_OUTPUT%\lib"
set "RUN_OUTPUT=%NATIVE_OUTPUT%\native-run"
set "EXE_WORKDIR=%NATIVE_OUTPUT%\work\exe"
set "DLL_WORKDIR=%NATIVE_OUTPUT%\work\dll"
set "LIB_WORKDIR=%NATIVE_OUTPUT%\work\lib"
set "RUN_WORKDIR=%NATIVE_OUTPUT%\work\native-run"

call "%~dp0test_dm.bat" --build-cfg release %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\release" --work-dir "%RUN_WORKDIR%\release" --build-cfg release %*
if errorlevel 1 exit /b %errorlevel%
for %%K in (dll lib) do (
    for %%S in (lexer parser sema jit native) do (
        swc_devmode test --artifact-kind %%K -d "%ROOT%\bin\tests\%%S" --out-dir "%NATIVE_OUTPUT%\%%K" --work-dir "%NATIVE_OUTPUT%\work\%%K" --build-cfg release %*
        if errorlevel 1 exit /b 1
    )
)

call "%~dp0test_dm.bat" --build-cfg debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\debug" --work-dir "%RUN_WORKDIR%\debug" --build-cfg debug %*
if errorlevel 1 exit /b %errorlevel%
for %%K in (dll lib) do (
    for %%S in (lexer parser sema jit native) do (
        swc_devmode test --artifact-kind %%K -d "%ROOT%\bin\tests\%%S" --out-dir "%NATIVE_OUTPUT%\%%K" --work-dir "%NATIVE_OUTPUT%\work\%%K" --build-cfg debug %*
        if errorlevel 1 exit /b 1
    )
)

call "%~dp0test_dm.bat" --build-cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\fast-debug" --work-dir "%RUN_WORKDIR%\fast-debug" --build-cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
for %%K in (dll lib) do (
    for %%S in (lexer parser sema jit native) do (
        swc_devmode test --artifact-kind %%K -d "%ROOT%\bin\tests\%%S" --out-dir "%NATIVE_OUTPUT%\%%K" --work-dir "%NATIVE_OUTPUT%\work\%%K" --build-cfg fast-debug %*
        if errorlevel 1 exit /b 1
    )
)

call "%~dp0test_dm.bat" --build-cfg fast-compile %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\fast-compile" --work-dir "%RUN_WORKDIR%\fast-compile" --build-cfg fast-compile %*
if errorlevel 1 exit /b %errorlevel%
for %%K in (dll lib) do (
    for %%S in (lexer parser sema jit native) do (
        swc_devmode test --artifact-kind %%K -d "%ROOT%\bin\tests\%%S" --out-dir "%NATIVE_OUTPUT%\%%K" --work-dir "%NATIVE_OUTPUT%\work\%%K" --build-cfg fast-compile %*
        if errorlevel 1 exit /b 1
    )
)

exit /b 0
