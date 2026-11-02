@echo off
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0coverage.ps1" %*
exit /b %errorlevel%
