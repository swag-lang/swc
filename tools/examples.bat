@echo off
setlocal

rem Builds, runs, tests, or smokes the examples workspace.
rem
rem This is a shim. The tool itself is the Swag program under src/; everything here does is
rem name it and hand its command line over. Run it with -h for the usage.

set "SWAG_TOOL_NAME=examples"
set "SWAG_TOOL_ARGS=%*"
call "%~dp0_run.bat"
exit /b %ERRORLEVEL%
