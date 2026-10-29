@echo off
setlocal DisableDelayedExpansion
set "dm="
set "campaign=%~1"
set "compilerArgs=%*"
if /i "%~1"=="dm" (
    set "dm=dm"
    set "campaign=%~2"
    for /f "tokens=1,2,*" %%A in ("%*") do set "compilerArgs=%%C"
) else (
    for /f "tokens=1,*" %%A in ("%*") do set "compilerArgs=%%B"
)
if /i "%campaign%"=="-h" goto usage
if /i "%campaign%"=="--help" goto usage
if not defined campaign set "campaign=all"
if "%campaign:~0,1%"=="-" (
    set "campaign=all"
    set "compilerArgs=%*"
    if defined dm for /f "tokens=1,*" %%A in ("%*") do set "compilerArgs=%%B"
)
if /i "%campaign%"=="opengl" goto opengl
if /i "%campaign%"=="windows" goto windows
if /i "%campaign%"=="smoke" goto smoke
if /i "%campaign%"=="all" goto all
echo error: use opengl, windows, or smoke
exit /b 1
:opengl
call "%~dp0std.bat" %dm% test pixel --test-tag integration.renderer.opengl %compilerArgs%
exit /b %errorlevel%
:windows
call "%~dp0std.bat" %dm% test gui --test-tag integration.host.windows %compilerArgs%
exit /b %errorlevel%
:smoke
call "%~dp0scripts.bat" %dm% smoke %compilerArgs%
if errorlevel 1 exit /b 1
call "%~dp0examples.bat" %dm% smoke %compilerArgs%
if errorlevel 1 exit /b 1
call "%~dp0apps.bat" %dm% smoke %compilerArgs%
exit /b %errorlevel%
:all
call "%~dp0integrations.bat" %dm% opengl %compilerArgs%
if errorlevel 1 exit /b 1
call "%~dp0integrations.bat" %dm% windows %compilerArgs%
if errorlevel 1 exit /b 1
call "%~dp0integrations.bat" %dm% smoke %compilerArgs%
exit /b %errorlevel%
:usage
echo Usage: integrations.bat [dm] [opengl^|windows^|smoke] [swc options]
exit /b 0
