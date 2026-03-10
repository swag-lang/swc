@echo off

call "%~dp0test_dm.bat" --cfg release %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0test_dm.bat" --cfg debug %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0test_dm.bat" --cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0test_dm.bat" --cfg fast-compile %*
exit /b %errorlevel%
