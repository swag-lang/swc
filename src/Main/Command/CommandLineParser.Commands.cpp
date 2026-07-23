#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

void CommandLineParser::registerCommands()
{
    const std::string_view registeredBuildCfgs{cmdLine_->defaultBuildCfg.registeredConfigs.ptr, cmdLine_->defaultBuildCfg.registeredConfigs.length};
    std::vector<Utf8>      buildCfgChoices;
    if (!registeredBuildCfgs.empty())
    {
        size_t start = 0;
        while (start <= registeredBuildCfgs.size())
        {
            size_t end = registeredBuildCfgs.find('|', start);
            if (end == std::string_view::npos)
                end = registeredBuildCfgs.size();
            buildCfgChoices.emplace_back(registeredBuildCfgs.substr(start, end - start));
            if (end == registeredBuildCfgs.size())
                break;
            start = end + 1;
        }
    }

    configSchema_.addEnum("command", &cmdLine_->command,
                          {
                              {"format", CommandKind::Format},
                              {"syntax", CommandKind::Syntax},
                              {"sema", CommandKind::Sema},
#if SWC_HAS_UNITTEST
                              {"unittest", CommandKind::Unittest},
#endif
                              {"test", CommandKind::Test},
                              {"build", CommandKind::Build},
                              {"run", CommandKind::Run},
                          },
                          "Select the command to execute",
                          {&StructConfigAssignHook::setBoolTrue, &cmdLine_->commandExplicit});

    add(HelpOptionGroup::Input, "all", "--config-file", "-cf",
        &cmdLine_->configFile,
        "Read options from a config file before applying explicit CLI flags; resolve its relative paths from the config file directory",
        false);
    add(HelpOptionGroup::Input, "all", "--directory", "-d",
        &cmdLine_->directories,
        "Process one or more directories recursively for input files; with --module-file, resolve relative paths from the module file directory");
    add(HelpOptionGroup::Input, "all", "--file", "-f",
        &cmdLine_->files,
        "Process one or more individual files directly; with --module-file, resolve relative paths from the module file directory");
    add(HelpOptionGroup::Input, "all", "--file-filter", "-ff",
        &cmdLine_->fileFilter,
        "Keep input paths that contain this substring");
    add(HelpOptionGroup::Input, "all", "--module", "-mf",
        &cmdLine_->modulePath,
        "Compile the module at this path");
    add(HelpOptionGroup::Input, "all", "--module-file", nullptr,
        &cmdLine_->moduleFilePath,
        "Run this module setup file before compiling the rest of the module; derive the module root and relative input paths from its parent directory");
    add(HelpOptionGroup::Input, "sema test build run", "--workspace", "-w",
        &cmdLine_->workspacePath,
        "Use a workspace containing modules/<module>/module.swg and modules/<module>/src; the workspace owns its .output and .tmp directories and excludes --module, --module-file, --directory, and --file");
    add(HelpOptionGroup::Input, "sema test build run", "--workspace-module", "-m",
        &cmdLine_->workspaceModuleFilter,
        "With --workspace, compile only this module and its internal workspace dependencies");
    add(HelpOptionGroup::Input, "sema test build run", "--import-api-module", nullptr,
        &cmdLine_->importApiModules,
        "Resolve a generated public API dependency by module name through <compiler-root>/std/.output/<module>/<matching-config>");
    add(HelpOptionGroup::Input, "sema test build run", "--import-api-dir", nullptr,
        &cmdLine_->importApiDirs,
        "Add a read-only dependency root containing generated public API files (.swg/.swgs) under <module>/<backend>/<build-cfg>/<arch>");
    add(HelpOptionGroup::Input, "sema test build run", "--import-api-file", nullptr,
        &cmdLine_->importApiFiles,
        "Add one generated public API file (.swg/.swgs) to the compilation input");
    add(HelpOptionGroup::Input, "sema build run", "--export-api-dir", nullptr,
        &cmdLine_->exportApiDir,
        "Write the module public API to this directory after a successful semantic pass");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--arch", "-a",
            &cmdLine_->targetArch,
            {
                {"x86_64", Runtime::TargetArch::X86_64},
            },
            "Set the target architecture used by #arch and compiler target queries");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--build-cfg", "-bc",
            &cmdLine_->buildCfg,
            std::move(buildCfgChoices),
            "Set the registered build configuration used by #cfg and @compiler.getBuildCfg()");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--artifact-kind", "-ak",
            &cmdLine_->backendKind,
            {
                {"executable", Runtime::BuildCfgBackendKind::Executable},
                {"shared-library", Runtime::BuildCfgBackendKind::SharedLibrary},
                {"static-library", Runtime::BuildCfgBackendKind::StaticLibrary},
                {"export", Runtime::BuildCfgBackendKind::Export},
            },
            "Select the backend kind exposed through @compiler.getBuildCfg(); export builds produce dependency and API output without a native artifact",
            true,
            {&StructConfigAssignHook::setBoolTrue, &cmdLine_->artifactKindExplicit});
    add(HelpOptionGroup::Target, "sema test build run", "--cpu", "-cpu",
        &cmdLine_->targetCpu,
        "Set the target CPU string used by #cpu and compiler target queries");
    add(HelpOptionGroup::Target, "sema test build run", "--artifact-name", "-n",
        &cmdLine_->name,
        "Set the artifact name exposed through @compiler.getBuildCfg() and used for native outputs");
    add(HelpOptionGroup::Target, "sema test build run", "--module-namespace", nullptr,
        &cmdLine_->moduleNamespace,
        "Override the module namespace exposed through @compiler.getBuildCfg() and used as the semantic module root");
    add(HelpOptionGroup::Target, "sema test build run", "--out-dir", "-od",
        &cmdLine_->outDir,
        "Set the artifact output directory exposed through @compiler.getBuildCfg()");
    add(HelpOptionGroup::Target, "sema test build run", "--work-dir", "-wd",
        &cmdLine_->workDir,
        "Set the work directory exposed through @compiler.getBuildCfg()");
    add(HelpOptionGroup::Target, "sema test build run", "--optimize", "-o",
        &cmdLine_->backendOptimize,
        "Enable backend optimization for JIT folding and native code generation");

    add(HelpOptionGroup::Compiler, "all", "--num-cores", "-j",
        &cmdLine_->numCores,
        "Set the maximum CPU core count; use 0 to detect it automatically");
    add(HelpOptionGroup::Compiler, "all", "--stats", "-st",
        &cmdLine_->stats,
        "Show runtime statistics after execution");
    add(HelpOptionGroup::Compiler, "all", "--stats-mem", "-stm",
        &cmdLine_->statsMem,
        "Show runtime memory statistics after execution");
    add(HelpOptionGroup::Compiler, "sema test build run", "--tag", nullptr,
        &cmdLine_->tags,
        "Register a compiler tag for #hastag and #gettag; use Name, Name = value, or Name: type = value");
    add(HelpOptionGroup::Compiler, "test run", "--run-arg", nullptr,
        &cmdLine_->runArgs,
        "Append one argument to every emitted executable launched by test or run; repeat the option to append more");
    add(HelpOptionGroup::Compiler, "test build run", "--publish", nullptr,
        &cmdLine_->publish,
        "Copy executable dependency DLLs and PDBs to the artifact output directory after a successful native link");
    add(HelpOptionGroup::Compiler, "sema test build run", "--rebuild", nullptr,
        &cmdLine_->rebuild,
        "With --workspace, recompile every selected module even when all generated outputs are up to date");

    addEnum<FileSystem::FilePathDisplayMode>(
        HelpOptionGroup::Diagnostics, "all", "--path-display", "-pd",
        &cmdLine_->filePathDisplay,
        {
            {"as-is", FileSystem::FilePathDisplayMode::AsIs},
            {"basename", FileSystem::FilePathDisplayMode::BaseName},
            {"absolute", FileSystem::FilePathDisplayMode::Absolute},
        },
        "Choose how diagnostics, stack traces, and source locations display file paths");
    add(HelpOptionGroup::Diagnostics, "all", "--diagnostic-id", "-di",
        &cmdLine_->errorId,
        "Show diagnostic identifiers");
    add(HelpOptionGroup::Diagnostics, "all", "--diagnostic-one-line", "-dl",
        &cmdLine_->diagOneLine,
        "Render each diagnostic on one line");

    add(HelpOptionGroup::Logging, "all", "--log-ascii", "-la",
        &cmdLine_->logAscii,
        "Restrict console output to ASCII and disable Unicode glyphs");
    add(HelpOptionGroup::Logging, "all", "--log-color", "-lc",
        &cmdLine_->logColor,
        "Colorize log output");
    add(HelpOptionGroup::Logging, "all", "--silent", "-s",
        &cmdLine_->silent,
        "Suppress all log output");
    add(HelpOptionGroup::Logging, "all", "--syntax-color", "-sc",
        &cmdLine_->syntaxColor,
        "Colorize source code in compiler output");
    add(HelpOptionGroup::Logging, "all", "--syntax-color-lum", "-scl",
        &cmdLine_->syntaxColorLum,
        "Set syntax-color luminosity from 0 to 100");

    add(HelpOptionGroup::Testing, "test", "--test-native", "-tn",
        &cmdLine_->testNative,
        "Run #test sources through the native backend");
    add(HelpOptionGroup::Testing, "test", "--test-jit", "-tj",
        &cmdLine_->testJit,
        "Run #test functions through the JIT during testing");
    add(HelpOptionGroup::Testing, "test", "--lex-only", nullptr,
        &cmdLine_->lexOnly,
        "Stop test inputs after lexing; excludes --syntax-only and --sema-only");
    add(HelpOptionGroup::Testing, "test", "--syntax-only", nullptr,
        &cmdLine_->syntaxOnly,
        "Stop test inputs after parsing; excludes --lex-only and --sema-only");
    add(HelpOptionGroup::Testing, "test", "--sema-only", nullptr,
        &cmdLine_->semaOnly,
        "Stop test inputs after semantic analysis; excludes --lex-only and --syntax-only");
    add(HelpOptionGroup::Testing, "test", "--output", nullptr,
        &cmdLine_->output,
        "Generate native artifacts during testing; use --no-output to keep JIT-only test runs in memory");
    add(HelpOptionGroup::Testing, "test", "--verbose-verify", "-vv",
        &cmdLine_->verboseVerify,
        "Show diagnostics that source-driven tests normally match and suppress");
    add(HelpOptionGroup::Testing, "test", "--verbose-verify-filter", "-vvf",
        &cmdLine_->verboseVerifyFilter,
        "Keep --verbose-verify messages and diagnostic IDs that match this string");

    add(HelpOptionGroup::Development, "all", "--dry-run", "-dr",
        &cmdLine_->dryRun,
        "Preview planned stages, outputs, and external commands without executing compile-time code, native tools, tests, or emitted artifacts");
    add(HelpOptionGroup::Development, "all", "--show-config", nullptr,
        &cmdLine_->showConfig,
        "Show the resolved command, environment, toolchain, and native artifact configuration, then exit");
    add(HelpOptionGroup::Development, "all", "--dev-stop", "-ds",
        &CompilerInstance::dbgDevStop,
        "Open a message box when the compiler reports an error");
    add(HelpOptionGroup::Development, "all", "--dev-full", "-df",
        &cmdLine_->devFull,
        "Enable every compiled-in development test and validator");

#if SWC_HAS_UNITTEST
    add(HelpOptionGroup::Development, "unittest", "--verbose-unittest", "-vu",
        &cmdLine_->verboseUnittest,
        "Show the status of each internal unit test");
#endif

#if SWC_HAS_VALIDATE_MICRO
    add(HelpOptionGroup::Development, "all", "--validate-micro", nullptr,
        &cmdLine_->validateMicro,
        "Validate Micro IR legality and pass invariants");
#endif

#if SWC_HAS_VALIDATE_NATIVE
    add(HelpOptionGroup::Development, "all", "--validate-native", nullptr,
        &cmdLine_->validateNative,
        "Validate the native backend, including constant relocations");
#endif

#if SWC_DEV_MODE
    add(HelpOptionGroup::Development, "all", "--randomize", "-rz",
        &cmdLine_->randomize,
        "Randomize single-threaded job scheduling; implies --num-cores=1");
    add(HelpOptionGroup::Development, "all", "--seed", "-rs",
        &cmdLine_->randSeed,
        "Set the --randomize seed; implies --randomize and --num-cores=1");
#endif
}

SWC_END_NAMESPACE();
