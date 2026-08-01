@echo off
rem Run a full performance campaign: rebuild the compiler, measure it against every
rem other toolchain, append the result to the history, regenerate bench.html.
rem
rem   run-benchmark-campaign.bat                             a full campaign
rem   run-benchmark-campaign.bat --label "what changed"      the same, with a note in the history
rem   run-benchmark-campaign.bat --quick                     smoke test, one repetition, not recorded
rem   run-benchmark-campaign.bat --report-only               regenerate the page, measure nothing
rem
rem See ..\bench\README.md before changing anything about how it measures.

setlocal
for %%I in ("%~dp0..\bench") do set "BENCH_DIR=%%~fI"

rem Prefer a directly installed Python 3. The Windows launcher can select an
rem incomplete registered installation and emit a misleading prefix warning.
where python >nul 2>&1
if errorlevel 1 goto try_python_launcher
python -c "import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)" >nul 2>&1
if errorlevel 1 goto try_python_launcher
python "%BENCH_DIR%\campaign.py" %*
exit /b %ERRORLEVEL%

:try_python_launcher
where py >nul 2>&1
if errorlevel 1 goto missing_python
py -3 "%BENCH_DIR%\campaign.py" %*
exit /b %ERRORLEVEL%

:missing_python
echo Python 3 is required to run the benchmark, and neither `py` nor `python` is on PATH.
exit /b 1
