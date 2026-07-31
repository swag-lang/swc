@echo off
rem Run a full performance campaign: rebuild the compiler, measure it against every
rem other toolchain, append the result to the history, regenerate bench.html.
rem
rem   bench.bat                             a full campaign
rem   bench.bat --label "what changed"      the same, with a note in the history
rem   bench.bat --quick                     smoke test, one repetition, not recorded
rem   bench.bat --report-only               regenerate the page, measure nothing
rem
rem See README.md before changing anything about how it measures.

setlocal
for %%I in ("%~f0") do set "BENCH_DIR=%%~dpI"

where py >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    py -3 "%BENCH_DIR%campaign.py" %*
    exit /b %ERRORLEVEL%
)

where python >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    python "%BENCH_DIR%campaign.py" %*
    exit /b %ERRORLEVEL%
)

echo Python 3 is required to run the benchmark, and neither `py` nor `python` is on PATH.
exit /b 1
