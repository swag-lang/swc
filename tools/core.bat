@echo off
setlocal

for %%I in ("%~f0") do set "TOOLS_DIR=%%~dpI"
call "%TOOLS_DIR%_common.bat" :init "%TOOLS_DIR%" "%~1"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if /I "%~1"=="dm" shift

set "WIN32_BIN_REL=std\modules\win32"
set "XINPUT_BIN_REL=std\modules\xinput"
set "CORE_BIN_REL=std\modules\core"
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
set "XINPUT_API_DIR=%OUTPUT_ROOT%\dep\xinput"
set "WIN32_MODULE_FILE=%ROOT%\bin\%WIN32_BIN_REL%\module.swg"
set "XINPUT_MODULE_FILE=%ROOT%\bin\%XINPUT_BIN_REL%\module.swg"
set "CORE_MODULE_FILE=%ROOT%\bin\%CORE_BIN_REL%\module.swg"

call "%TOOLS_DIR%_common.bat" :set_paths "%WIN32_BIN_REL%" "export" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

"%SWC_EXE%" build --no-unittest --module-file "%WIN32_MODULE_FILE%" -d "src" --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --export-api-dir "%WIN32_API_DIR%"%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

call "%TOOLS_DIR%_common.bat" :set_paths "%XINPUT_BIN_REL%" "export" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

"%SWC_EXE%" build --no-unittest --module-file "%XINPUT_MODULE_FILE%" -d "src" --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --import-api-dir "%WIN32_API_DIR%" --export-api-dir "%XINPUT_API_DIR%"%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

call "%TOOLS_DIR%_common.bat" :set_paths "%CORE_BIN_REL%" "executable" "%BUILD_CFG%"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

"%SWC_EXE%" test --module-file "%CORE_MODULE_FILE%" -d "src" --artifact-kind executable --out-dir "%OUT_DIR%" --work-dir "%WORK_DIR%" --build-cfg %BUILD_CFG% --import-api-dir "%WIN32_API_DIR%" --import-api-dir "%XINPUT_API_DIR%"%EXTRA_ARGS%
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%

exit /b 0
