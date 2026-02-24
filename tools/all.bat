@echo off

call "%~dp0_suite.bat" syntax swc %*
if errorlevel 1 exit /b %errorlevel%

call "%~dp0_suite.bat" sema swc --no-optimize %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" sema swc --optimize --no-optimize-size %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" sema swc --optimize --optimize-size %*
if errorlevel 1 exit /b %errorlevel%

exit /b 0
