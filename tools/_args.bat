@echo off

rem Parses the argument grammar shared by every repository tool and resolves the compiler to
rem launch. The caller sets TOOLS_DIR first, plus its own SWC_COMMAND default when it has one.
rem
rem     call "%TOOLS_DIR%_args.bat" "<accepted commands>" %*
rem
rem Positionals come first, options after:
rem
rem     tool [dm] [<command>] [<name>] [options...]
rem
rem 'dm' selects bin/swc_devmode.exe. <command> is one of the accepted commands. <name> is a
rem module, suite, or script name. The first token starting with '-' closes the positional part,
rem so an option value can never be mistaken for a name.
rem
rem Sets ROOT, SWC_BIN_DIR, SWC_EXE, SWC_MODE, SWAG_PATH, TARGET_ARCH, MODE_ARG, SWC_COMMAND,
rem MODULE, BUILD_CFG, ALL_CFG, WANT_HELP, WORKSPACE_ARGS, EXTRA_ARGS, RUN_ARGS, APP_ARGS, and
rem RUN_ARG_NAMES, the run-argument values alone, unquoted and always defined, for tools that
rem need to know whether the caller already asked for something.

if not defined TOOLS_DIR exit /b 1

set "ACCEPTED_COMMANDS=%~1"
shift

for %%I in ("%TOOLS_DIR%..") do set "ROOT=%%~fI"
set "SWC_BIN_DIR=%ROOT%\bin"
set "SWC_EXE=%SWC_BIN_DIR%\swc.exe"
set "SWC_MODE=release"
set "SWAG_PATH=%SWC_BIN_DIR%"
if not defined TARGET_ARCH set "TARGET_ARCH=x86_64"

set "MODE_ARG="
set "MODULE="
set "BUILD_CFG=fast-debug"
set "ALL_CFG="
set "WANT_HELP="
set "WORKSPACE_ARGS="
set "EXTRA_ARGS="
set "RUN_ARGS="
set "APP_ARGS="
set "RUN_ARG_NAMES= "

if /I not "%~1"=="dm" goto parse_command
set "MODE_ARG=dm"
set "SWC_EXE=%SWC_BIN_DIR%\swc_devmode.exe"
set "SWC_MODE=devmode"
shift

:parse_command
if "%~1"=="" exit /b 0
set "ARG_TOKEN=%~1"
if "%ARG_TOKEN:~0,1%"=="-" goto parse_options
if "%ARG_TOKEN:~0,1%"=="/" goto parse_options
set "IS_COMMAND="
for %%C in (%ACCEPTED_COMMANDS%) do if /I "%%C"=="%ARG_TOKEN%" set "IS_COMMAND=1"
if not defined IS_COMMAND goto parse_name
set "SWC_COMMAND=%ARG_TOKEN%"
shift

:parse_name
if "%~1"=="" exit /b 0
set "ARG_TOKEN=%~1"
if "%ARG_TOKEN:~0,1%"=="-" goto parse_options
if "%ARG_TOKEN:~0,1%"=="/" goto parse_options
set "MODULE=%ARG_TOKEN%"
shift

:parse_options
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" goto want_help
if /I "%~1"=="--help" goto want_help
if "%~1"=="/?" goto want_help
if /I "%~1"=="-bc" goto opt_build_cfg
if /I "%~1"=="--build-cfg" goto opt_build_cfg
if /I "%~1"=="--all-cfg" goto opt_all_cfg
if /I "%~1"=="-m" goto opt_module
if /I "%~1"=="--workspace-module" goto opt_module
if /I "%~1"=="--target-arch" goto opt_target_arch
if /I "%~1"=="--frames" goto opt_frames
if /I "%~1"=="--run-timeout" goto opt_run_timeout
if /I "%~1"=="--run-arg" goto opt_run_arg
set "EXTRA_ARGS=%EXTRA_ARGS% %1"
shift
goto parse_options

:opt_build_cfg
if "%~2"=="" goto missing_value
set "BUILD_CFG=%~2"
shift
shift
goto parse_options

:opt_all_cfg
set "ALL_CFG=1"
shift
goto parse_options

:opt_module
if "%~2"=="" goto missing_value
set "MODULE=%~2"
shift
shift
goto parse_options

:opt_target_arch
if "%~2"=="" goto missing_value
set "TARGET_ARCH=%~2"
set "EXTRA_ARGS=%EXTRA_ARGS% --target-arch %~2"
shift
shift
goto parse_options

rem --frames and --run-timeout only mean something to a run or a smoke, so they are kept apart
rem from EXTRA_ARGS: a tool that builds the standard library first must not forward them to it.
:opt_frames
if "%~2"=="" goto missing_value
set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --frames %~2"
shift
shift
goto parse_options

:opt_run_timeout
if "%~2"=="" goto missing_value
set "WORKSPACE_ARGS=%WORKSPACE_ARGS% --run-timeout %~2"
shift
shift
goto parse_options

:opt_run_arg
shift
if "%~1"=="" goto missing_value
set "RUN_ARG_VALUE=%~1"
shift

:opt_run_arg_suffix
if "%~1"=="" goto opt_run_arg_commit
set "ARG_TOKEN=%~1"
if "%ARG_TOKEN:~0,1%"=="-" goto opt_run_arg_commit
rem cmd.exe tokenizes '=' in batch arguments. Reassemble values such as name=value.
set "RUN_ARG_VALUE=%RUN_ARG_VALUE%=%ARG_TOKEN%"
shift
goto opt_run_arg_suffix

:opt_run_arg_commit
set "RUN_ARGS=%RUN_ARGS% --run-arg "%RUN_ARG_VALUE%""
set "APP_ARGS=%APP_ARGS% "%RUN_ARG_VALUE%""
set "RUN_ARG_NAMES=%RUN_ARG_NAMES%%RUN_ARG_VALUE% "
goto parse_options

:want_help
set "WANT_HELP=1"
exit /b 0

:missing_value
echo An option is missing its value.
exit /b 1
