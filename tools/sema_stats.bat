@echo off
call "%~dp0_suite.bat" sema swc_stats %*
exit /b %errorlevel%
