@echo off
setlocal

rem Builds or tests the standard library, whole or one module.
rem
rem This is a shim. The tool itself is the Swag program under src/; everything here does is
rem name it and hand its command line over. Run it with -h for the usage.

set "SWAG_TOOL_NAME=std"
set "SWAG_TOOL_ARGS=%*"
call "%~dp0_run.bat"
exit /b %ERRORLEVEL%
