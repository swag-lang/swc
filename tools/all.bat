@echo off

call "%~dp0test.bat" --cfg release %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0test.bat" --cfg debug %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0test.bat" --cfg fast-debug %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0test.bat" --cfg fast-compile %*
exit /b %errorlevel%
