@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

set "CORE_MODULE=%ROOT%\bin\std\modules\core"
set "WIN32_API_DIR=%OUTPUT_ROOT%\dep\win32"
set "XINPUT_API_DIR=%OUTPUT_ROOT%\dep\xinput"
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
%SWC_EXE% sema -m "%CORE_MODULE%" --module-namespace Core --import-api-dir "%WIN32_API_DIR%" --import-api-dir "%XINPUT_API_DIR%" --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

exit /b 0
