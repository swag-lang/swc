@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%common.bat" :init "%TOOLS_DIR%" "%~1"
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="dm" shift

set "WIN32_BIN_REL=std\modules\win32"
set "GDI32_BIN_REL=std\modules\gdi32"
set "XAUDIO2_BIN_REL=std\modules\xaudio2"
set "XINPUT_BIN_REL=std\modules\xinput"
set "BUILD_CFG=fast-debug"
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--build-cfg" (
    set "BUILD_CFG=%~2"
    shift
    shift
    goto parse_args
)
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_args

:run
set "WIN32_API_DIR=%OUTPUT_ROOT%\dep\win32"
set "GDI32_API_DIR=%OUTPUT_ROOT%\dep\gdi32"
set "XAUDIO2_API_DIR=%OUTPUT_ROOT%\dep\xaudio2"
set "XINPUT_API_DIR=%OUTPUT_ROOT%\dep\xinput"

call "%TOOLS_DIR%common.bat" :set_paths "%WIN32_BIN_REL%" "shared-library" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%

%SWC_EXE% build -m "%ROOT%\bin\%WIN32_BIN_REL%" --artifact-kind shared-library --module-namespace Win32 --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --export-api-dir "%WIN32_API_DIR%" --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

call "%TOOLS_DIR%common.bat" :set_paths "%GDI32_BIN_REL%" "shared-library" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%

%SWC_EXE% build -m "%ROOT%\bin\%GDI32_BIN_REL%" --artifact-kind shared-library --module-namespace Gdi32 --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --import-api-dir "%WIN32_API_DIR%" --export-api-dir "%GDI32_API_DIR%" --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

call "%TOOLS_DIR%common.bat" :set_paths "%XAUDIO2_BIN_REL%" "shared-library" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%

%SWC_EXE% build -m "%ROOT%\bin\%XAUDIO2_BIN_REL%" --artifact-kind shared-library --module-namespace XAudio2 --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --import-api-dir "%WIN32_API_DIR%" --export-api-dir "%XAUDIO2_API_DIR%" --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

call "%TOOLS_DIR%common.bat" :set_paths "%XINPUT_BIN_REL%" "shared-library" "%BUILD_CFG%"
if errorlevel 1 exit /b %errorlevel%

%SWC_EXE% build -m "%ROOT%\bin\%XINPUT_BIN_REL%" --artifact-kind shared-library --module-namespace XInput --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --import-api-dir "%WIN32_API_DIR%" --export-api-dir "%XINPUT_API_DIR%" --gen-dir "%GEN_DIR%"%EXTRA_ARGS%
if errorlevel 1 exit /b 1

exit /b 0
