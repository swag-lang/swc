@echo off
setlocal

rem Copies shared and app-owned runtime files beside one built application.

if "%~4"=="" exit /b 1
set "ROOT=%~1"
set "APP_NAME=%~2"
set "BUILD_CFG=%~3"
set "TARGET_ARCH=%~4"
set "APPS_WORKSPACE=%ROOT%\bin\apps"
set "MODULE_DIR=%APPS_WORKSPACE%\modules\%APP_NAME%"
set "APP_DIR=%APPS_WORKSPACE%\.output\%APP_NAME%\executable\%BUILD_CFG%\%TARGET_ARCH%"

if not exist "%APP_DIR%\%APP_NAME%.exe" (
    echo Application executable is missing: "%APP_DIR%\%APP_NAME%.exe"
    exit /b 1
)

for /d %%D in ("%APPS_WORKSPACE%\.dep\*") do (
    for %%F in ("%%~fD\shared-library\%BUILD_CFG%\%TARGET_ARCH%\*.dll") do (
        if exist "%%~fF" copy /Y "%%~fF" "%APP_DIR%\%%~nxF" >nul || exit /b 1
    )
)

if /I "%APP_NAME%"=="sCrypt" (
    copy /Y "%MODULE_DIR%\vendor\winfsp\runtime\winfsp-x64.dll" "%APP_DIR%\winfsp-x64.dll" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\vendor\winfsp\runtime\winfsp-x64.sys" "%APP_DIR%\winfsp-x64.sys" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\vendor\winfsp\LICENSE.txt" "%APP_DIR%\WinFsp-LICENSE.txt" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\LICENSE.md" "%APP_DIR%\LICENSE.md" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\THIRD-PARTY-NOTICES.md" "%APP_DIR%\THIRD-PARTY-NOTICES.md" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\README.md" "%APP_DIR%\README.md" >nul || exit /b 1
    if exist "%APP_DIR%\winfsp-2.1.25156.msi" del /Q "%APP_DIR%\winfsp-2.1.25156.msi"
)

exit /b 0
