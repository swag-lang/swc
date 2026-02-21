@echo off
call "%~dp0_suite.bat" sema swc %*
exit /b %errorlevel%
