@echo off
setlocal

rem Formats every Swag source workspace in the repository.
rem
rem     format.bat [dm] [options...]

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_args.bat" "" %*
if errorlevel 1 exit /b 1
if defined WANT_HELP goto help

call "%TOOLS_DIR%_common.bat" :run_swc format ^
 -d "%ROOT%\bin\examples" ^
 -d "%ROOT%\bin\apps" ^
 -d "%ROOT%\bin\reference" ^
 -d "%ROOT%\bin\runtime" ^
 -d "%ROOT%\bin\std" ^
 -d "%ROOT%\bin\unittests"%EXTRA_ARGS%
exit /b %ERRORLEVEL%

:help
echo Formats every Swag source workspace in the repository, in place.
echo.
echo   format.bat [dm] [options...]
echo.
echo This rewrites tracked sources. It is a maintenance step, never a test.
exit /b 0
