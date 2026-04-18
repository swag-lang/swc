@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "WIN32_MODULE=%ROOT%\bin\std\modules\win32"
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
set "EXTRA_ARGS=!EXTRA_ARGS! %~1"
shift
goto parse_args

:run
swc_devmode build -m "%WIN32_MODULE%" !EXTRA_ARGS!
if errorlevel 1 exit /b 1

exit /b 0
