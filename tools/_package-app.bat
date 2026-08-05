@echo off
setlocal

rem Copies the app-owned runtime files beside one built application.
rem
rem     _package-app.bat <root> <application> <build configuration> <target architecture>
rem
rem The std shared libraries are not copied here: the compiler publishes them itself when the
rem tools pass --publish, and it removes any it did not publish. Copying them from this script
rem as well would only mean the next link deletes them again.

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

if /I "%APP_NAME%"=="sCrypt" (
    copy /Y "%MODULE_DIR%\vendor\winfsp\runtime\winfsp-x64.dll" "%APP_DIR%\winfsp-x64.dll" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\vendor\winfsp\runtime\winfsp-x64.sys" "%APP_DIR%\winfsp-x64.sys" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\vendor\winfsp\LICENSE.txt" "%APP_DIR%\WinFsp-LICENSE.txt" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\LICENSE.md" "%APP_DIR%\LICENSE.md" >nul || exit /b 1
    copy /Y "%MODULE_DIR%\THIRD-PARTY-NOTICES.md" "%APP_DIR%\THIRD-PARTY-NOTICES.md" >nul || exit /b 1
    if exist "%APP_DIR%\winfsp-2.1.25156.msi" del /Q "%APP_DIR%\winfsp-2.1.25156.msi"
)

exit /b 0
