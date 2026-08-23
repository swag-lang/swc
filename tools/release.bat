@echo off
setlocal

set "MSBUILD="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "delims=" %%I in ('where msbuild 2^>nul') do if not defined MSBUILD set "MSBUILD=%%I"

if not defined MSBUILD (
    if exist "%VSWHERE%" (
        for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find MSBuild\**\Bin\amd64\MSBuild.exe`) do if not defined MSBUILD set "MSBUILD=%%I"
    )
)

if not defined MSBUILD (
    echo Error: MSBuild with the Visual C++ x64 tools was not found. 1>&2
    exit /b 1
)

pushd "%~dp0.."
"%MSBUILD%" swc.sln /m /p:Configuration=Release /p:Platform=x64
set "BUILD_EXIT=%ERRORLEVEL%"
popd

exit /b %BUILD_EXIT%
