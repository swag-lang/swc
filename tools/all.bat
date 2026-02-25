@echo off

for %%C in (release debug fast-debug fast-compile) do (
    echo.
    echo [all.bat] Running config: %%C

    call "%~dp0_suite.bat" syntax swc --cfg %%C %*
    if errorlevel 1 exit /b %errorlevel%

    call "%~dp0_suite.bat" sema swc --cfg %%C --no-optimize %*
    if errorlevel 1 exit /b %errorlevel%
    call "%~dp0_suite.bat" sema swc --cfg %%C --optimize %*
    if errorlevel 1 exit /b %errorlevel%
)

exit /b 0
