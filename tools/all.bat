@echo off

call "%~dp0_all_matrix.bat" all.bat swc %*
exit /b %errorlevel%
