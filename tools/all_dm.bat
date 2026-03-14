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
swc_devmode test --artifact-kind dll -d "%ROOT%\bin\tests" --out-dir "%DLL_OUTPUT%" --work-dir "%DLL_WORKDIR%" --build-cfg release %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind lib -d "%ROOT%\bin\tests" --out-dir "%LIB_OUTPUT%" --work-dir "%LIB_WORKDIR%" --build-cfg release %*
if errorlevel 1 exit /b %errorlevel%

call "%~dp0test_dm.bat" --build-cfg debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\debug" --work-dir "%RUN_WORKDIR%\debug" --build-cfg debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind dll -d "%ROOT%\bin\tests" --out-dir "%DLL_OUTPUT%" --work-dir "%DLL_WORKDIR%" --build-cfg debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind lib -d "%ROOT%\bin\tests" --out-dir "%LIB_OUTPUT%" --work-dir "%LIB_WORKDIR%" --build-cfg debug %*
if errorlevel 1 exit /b %errorlevel%

call "%~dp0test_dm.bat" --build-cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\fast-debug" --work-dir "%RUN_WORKDIR%\fast-debug" --build-cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind dll -d "%ROOT%\bin\tests" --out-dir "%DLL_OUTPUT%" --work-dir "%DLL_WORKDIR%" --build-cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind lib -d "%ROOT%\bin\tests" --out-dir "%LIB_OUTPUT%" --work-dir "%LIB_WORKDIR%" --build-cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%

call "%~dp0test_dm.bat" --build-cfg fast-compile %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode run -d "%ROOT%\bin\tests\native" --out-dir "%RUN_OUTPUT%\fast-compile" --work-dir "%RUN_WORKDIR%\fast-compile" --build-cfg fast-compile %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind dll -d "%ROOT%\bin\tests" --out-dir "%DLL_OUTPUT%" --work-dir "%DLL_WORKDIR%" --build-cfg fast-compile %*
if errorlevel 1 exit /b %errorlevel%
swc_devmode test --artifact-kind lib -d "%ROOT%\bin\tests" --out-dir "%LIB_OUTPUT%" --work-dir "%LIB_WORKDIR%" --build-cfg fast-compile %*
exit /b %errorlevel%
