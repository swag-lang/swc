@echo off
python "%~dp0tool.py" unittests %*
exit /b %errorlevel%
