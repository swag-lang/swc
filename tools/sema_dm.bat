@echo off
call "%~dp0_suite.bat" sema swc_devmode %*
exit /b %errorlevel%
