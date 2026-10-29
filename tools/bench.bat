@echo off
setlocal DisableDelayedExpansion
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
pushd "%~dp0.."
where python.exe >nul 2>&1
if errorlevel 1 goto pythonLauncher
python bench\campaign.py %*
set "result=%ERRORLEVEL%"
goto done
:pythonLauncher
py -3 bench\campaign.py %*
set "result=%ERRORLEVEL%"
:done
popd
exit /b %result%
:usage
echo Usage: bench.bat [campaign options]
exit /b 0
