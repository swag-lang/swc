@echo off

call "%~dp0_all_matrix.bat" full.bat swc %*
exit /b %errorlevel%
