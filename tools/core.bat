@echo off
setlocal EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "CORE_MODULE=%ROOT%\bin\std\modules\core"
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
set "EXTRA_ARGS=!EXTRA_ARGS! %~1"
shift
goto parse_args

:run
swc syntax -m "%CORE_MODULE%" !EXTRA_ARGS!
if errorlevel 1 exit /b 1

exit /b 0
