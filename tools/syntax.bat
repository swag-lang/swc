@echo off
call "%~dp0_suite.bat" syntax swc %*
exit /b %errorlevel%
