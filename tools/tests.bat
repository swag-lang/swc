@echo off
python "%~dp0tool.py" tests %*
exit /b %errorlevel%
