@echo off
call "%~dp0_suite.bat" test swc %*
exit /b %errorlevel%
