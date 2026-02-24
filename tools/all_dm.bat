@echo off

call "%~dp0_suite.bat" syntax swc_devmode %*
if errorlevel 1 exit /b %errorlevel%

call "%~dp0_suite.bat" sema swc_devmode --no-optimize %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" sema swc_devmode --optimize --no-optimize-size %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" sema swc_devmode --optimize --optimize-size %*
if errorlevel 1 exit /b %errorlevel%

exit /b 0
