@echo off
call "%~dp0_tool.bat" std %*
exit /b %errorlevel%
