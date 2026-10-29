@echo off
call "%~dp0_tool.bat" reference %*
exit /b %errorlevel%
