@echo off
setlocal

rem Installs a freshly validated compiler as the one the tools themselves run on.
rem
rem     promote.bat
rem
rem The tools are Swag programs, so something has to compile them, and that something must never
rem be the compiler under test: a tool whose job is to report that a new build is broken cannot be
rem compiled by it. tools\swc.exe is therefore a copy of the last compiler a full campaign proved,
rem and tools\host holds the standard library it was proved against.
rem
rem Promote only after 'tests.bat --all-cfg' is green with bin\swc.exe. This step accepts whatever
rem is in bin right now; nothing here checks it, deliberately, because the check is the campaign.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"

if not exist "%ROOT%\bin\swc.exe" goto missing_compiler

echo Installing bin\swc.exe as the pinned tools compiler...
copy /Y "%ROOT%\bin\swc.exe" "%TOOLS_DIR%swc.exe" >nul || exit /b 1

rem The tools import 'core', and they must not read it from the output the campaign rewrites: a
rem library the host built there would look up to date to the compiler under test, which would
rem then be measured against artifacts it never produced. So the host keeps its own copy, and the
rem shared output is removed afterwards to make the next campaign rebuild it from scratch.
echo Building the standard library the tools compile against...
"%TOOLS_DIR%swc.exe" build --workspace "%ROOT%\bin\std" --workspace-module core --build-cfg fast-debug || exit /b 1

if exist "%TOOLS_DIR%host" rmdir /S /Q "%TOOLS_DIR%host"
mkdir "%TOOLS_DIR%host\std" || exit /b 1
xcopy "%ROOT%\bin\std\.output" "%TOOLS_DIR%host\std\.output\" /E /I /Q /Y >nul || exit /b 1
rmdir /S /Q "%ROOT%\bin\std\.output"

echo.
echo Promoted. tools\swc.exe is now the pinned compiler and tools\host holds its library.
echo The shared bin\std\.output was removed, so the next build starts from a clean state.
exit /b 0

:missing_compiler
echo bin\swc.exe does not exist. Build the compiler before promoting it.
exit /b 1
