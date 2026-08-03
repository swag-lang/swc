@echo off
setlocal

rem Packages the VSCode extension after refreshing its generated image assets.
rem Install Node.js, then run `npm install -g vsce` before using this tool.
for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"
set "VSCODE_DIR=%ROOT%\vscode"

xcopy "%ROOT%\web\imgs\swag_icon.png" "%VSCODE_DIR%\images\" /Y || exit /b 1
xcopy "%ROOT%\web\imgs\syntax.png" "%VSCODE_DIR%\images\" /Y || exit /b 1

pushd "%VSCODE_DIR%" || exit /b 1
call vsce.cmd package
set "PACKAGE_ERROR=%ERRORLEVEL%"
popd
exit /b %PACKAGE_ERROR%
