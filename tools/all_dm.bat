@echo off

for %%C in (release debug fast-debug fast-compile) do (
    echo.
    echo [all_dm.bat] Running config: %%C

    call "%~dp0_suite.bat" syntax swc_devmode --cfg %%C %*
    if errorlevel 1 exit /b %errorlevel%

    call "%~dp0_suite.bat" sema swc_devmode --cfg %%C --no-optimize %*
    if errorlevel 1 exit /b %errorlevel%
    call "%~dp0_suite.bat" sema swc_devmode --cfg %%C --optimize %*
    if errorlevel 1 exit /b %errorlevel%
)

exit /b 0
