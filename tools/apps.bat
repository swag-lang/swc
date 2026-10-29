@echo off
call "%~dp0_tool.bat" apps %*
exit /b %errorlevel%
