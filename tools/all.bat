@echo off

call "%~dp0_suite.bat" syntax swc %*
if errorlevel 1 exit /b %errorlevel%

call "%~dp0_suite.bat" sema swc --backend-optimize off %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" sema swc --backend-optimize on --backend-optimize-favor speed %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0_suite.bat" sema swc --backend-optimize on --backend-optimize-favor size %*
if errorlevel 1 exit /b %errorlevel%

exit /b 0
