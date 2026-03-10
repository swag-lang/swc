@echo off

call "%~dp0_suite.bat" syntax swc_devmode %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" test swc_devmode %*
exit /b %errorlevel%
