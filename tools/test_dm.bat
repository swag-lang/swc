@echo off
call "%~dp0_suite.bat" test swc_devmode %*
exit /b %errorlevel%
