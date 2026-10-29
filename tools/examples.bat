@echo off
call "%~dp0_tool.bat" examples %*
exit /b %errorlevel%
