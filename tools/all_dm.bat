@echo off

call "%~dp0_all_matrix.bat" all_dm.bat swc_devmode %*
exit /b %errorlevel%
