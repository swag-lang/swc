@echo off
setlocal

rem Interactive owner-only build: intentionally uses the whole machine and a costly full LTCG link.
set "SWC_COMPILE_JOBS=%NUMBER_OF_PROCESSORS%"
set "SwcFullOptimization=true"

call "%~dp0release.bat"
exit /b %ERRORLEVEL%
