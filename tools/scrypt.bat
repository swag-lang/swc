@echo off
setlocal

rem Runs the privileged sCrypt/WinFsp end-to-end sandbox.
rem
rem This is a shim. The tool itself is the Swag program under src/; everything here does is
rem name it and hand its command line over. Run it with -h for the usage.

set "SWAG_TOOL_NAME=scrypt"
set "SWAG_TOOL_ARGS=%*"
call "%~dp0_run.bat"
exit /b %ERRORLEVEL%
