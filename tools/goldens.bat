@echo off
python "%~dp0tool.py" goldens %*
exit /b %errorlevel%
