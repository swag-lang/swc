@echo off
setlocal EnableDelayedExpansion

rem Promotes the snapshots a failing test left behind into the goldens they diverged from.
rem
rem A golden mismatch writes '<name>.actual.txt' or '<name>.actual.png' next to its reference and
rem fails. Once reviewed, this copies every actual over its golden and removes it. Recording is
rem deliberately a separate, explicit step: it accepts whatever the code currently produces.

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"

set "COUNT=0"
for /r "%ROOT%\bin" %%F in (*.actual.txt) do (
    set "ACTUAL=%%~fF"
    set "GOLDEN=!ACTUAL:.actual.txt=.txt!"
    move /y "!ACTUAL!" "!GOLDEN!" >nul || exit /b 1
    echo accepted %%~nxF
    set /a COUNT+=1
)

for /r "%ROOT%\bin" %%F in (*.actual.png) do (
    set "ACTUAL=%%~fF"
    set "GOLDEN=!ACTUAL:.actual.png=.png!"
    move /y "!ACTUAL!" "!GOLDEN!" >nul || exit /b 1
    echo accepted %%~nxF
    set /a COUNT+=1
)

if "%COUNT%"=="0" (
    echo no pending snapshot to accept
) else (
    echo %COUNT% golden^(s^) accepted - review them with git diff before committing
)

exit /b 0
