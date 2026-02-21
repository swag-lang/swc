@echo off

call "%~dp0_suite.bat" syntax swc %*
if errorlevel 1 exit /b %errorlevel%

for %%O in (O0 O1 O2 Os Oz) do (
    call "%~dp0_suite.bat" sema swc --backend-optimize %%O %*
    if errorlevel 1 exit /b %errorlevel%
)

exit /b 0
