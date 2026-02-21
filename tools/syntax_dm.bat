@echo off
call "%~dp0_suite.bat" syntax swc_devmode %*
exit /b %errorlevel%
