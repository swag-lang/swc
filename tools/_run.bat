@echo off

rem Runs one repository tool. Every entry point in this directory is a shim that names itself in
rem SWAG_TOOL_NAME, hands its raw command line over in SWAG_TOOL_ARGS, and calls this; all of the
rem logic lives in the Swag program under src/.
rem
rem The command line travels through an environment variable rather than through arguments
rem because cmd.exe splits a batch argument on '=' as well as on whitespace, so 'a=b' would reach
rem the tool as two tokens. The variable carries it verbatim, quoting included.
rem
rem The compiler here is pinned on purpose. It is the last one a full campaign proved, and it is
rem never the one under test: a tool has to be able to say that a freshly built compiler is
rem broken, which it cannot do if that compiler is what compiled and ran the tool. Refresh it
rem with promote.bat once a new build is green.

if not defined SWAG_TOOL_NAME exit /b 1
if not exist "%~dp0swc.exe" goto missing_host
if not exist "%~dp0host\std\.output" goto missing_host_library

set "SWAG_TOOL_ROOT=%~dp0.."
set "SWAG_PATH=%~dp0host"
"%~dp0swc.exe" "%~dp0src\main.swgs" --build-cfg fast-debug
exit /b %ERRORLEVEL%

:missing_host
echo tools\swc.exe is missing. The tools run on a pinned compiler rather than on the one being
echo built, so that a tool can still report a broken build. Build bin\swc.exe, then install it
echo here with tools\promote.bat.
exit /b 1

:missing_host_library
echo tools\host is missing the standard library the tools themselves are compiled against.
echo Run tools\promote.bat to produce it.
exit /b 1
