@echo off

call "%~dp0_suite.bat" syntax swc %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" test swc %*
exit /b %errorlevel%
