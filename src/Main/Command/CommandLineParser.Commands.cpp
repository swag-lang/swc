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
                              {"test", CommandKind::Test},
                              {"build", CommandKind::Build},
                              {"run", CommandKind::Run},
                          },
                          "Select the command to execute.",
                          {&StructConfigAssignHook::setBoolTrue, &cmdLine_->commandExplicit});

    add(HelpOptionGroup::Input, "all", "--config-file", "-cf",
        &cmdLine_->configFile,
        "Read command options from a config file before applying explicit CLI flags. Relative paths inside the file are resolved from the config file directory.",
        false);
    add(HelpOptionGroup::Input, "all", "--directory", "-d",
        &cmdLine_->directories,
        "Specify one or more directories to process recursively for input files.");
    add(HelpOptionGroup::Input, "all", "--file", "-f",
        &cmdLine_->files,
        "Specify one or more individual files to process directly.");
    add(HelpOptionGroup::Input, "all", "--file-filter", "-ff",
        &cmdLine_->fileFilter,
        "Apply a substring filter to input paths.");
    add(HelpOptionGroup::Input, "all", "--module", "-m",
        &cmdLine_->modulePath,
        "Specify a module path to compile.");
    add(HelpOptionGroup::Input, "sema build run", "--import-api-dir", nullptr,
        &cmdLine_->importApiDirs,
        "Add a directory of generated public API files (.swg/.swgs) to the compilation input.");
    add(HelpOptionGroup::Input, "sema build run", "--import-api-file", nullptr,
        &cmdLine_->importApiFiles,
        "Add one generated public API file (.swg/.swgs) to the compilation input.");
    add(HelpOptionGroup::Input, "sema build run", "--export-api-dir", nullptr,
        &cmdLine_->exportApiDir,
        "Generate the module public API into this directory after a successful semantic pass.");
    add(HelpOptionGroup::Input, "all", "--runtime", "-rt",
        &cmdLine_->runtime,
        "Include runtime files in the input set.");

    addEnum(HelpOptionGroup::Target, "sema test build run", "--arch", "-a",
            &cmdLine_->targetArch,
            {
                {"x86_64", Runtime::TargetArch::X86_64},
            },
            "Set the target architecture used by #arch and compiler target queries.");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--build-cfg", "-bc",
            &cmdLine_->buildCfg,
            std::move(buildCfgChoices),
            "Set the registered build configuration string used by #cfg and @compiler.getBuildCfg().");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--artifact-kind", "-ak",
            &cmdLine_->backendKind,
            {
                {"executable", Runtime::BuildCfgBackendKind::Executable},
                {"shared-library", Runtime::BuildCfgBackendKind::SharedLibrary},
                {"static-library", Runtime::BuildCfgBackendKind::StaticLibrary},
            },
            "Select the native artifact kind exposed through @compiler.getBuildCfg() and used by the native backend.",
            true,
            {&StructConfigAssignHook::setBoolTrue, &cmdLine_->artifactKindExplicit});
    add(HelpOptionGroup::Target, "sema test build run", "--cpu", "-cpu",
        &cmdLine_->targetCpu,
        "Set the target CPU string used by #cpu and compiler target queries.");
    add(HelpOptionGroup::Target, "sema test build run", "--artifact-name", "-n",
        &cmdLine_->name,
        "Set the artifact name exposed through @compiler.getBuildCfg() and used for native outputs.");
    add(HelpOptionGroup::Target, "sema test build run", "--module-namespace", nullptr,
        &cmdLine_->moduleNamespace,
        "Force the module namespace name exposed through @compiler.getBuildCfg() and used as the semantic module root.");
    add(HelpOptionGroup::Target, "sema test build run", "--out-dir", "-od",
        &cmdLine_->outDir,
        "Set the artifact output directory exposed through @compiler.getBuildCfg().");
    add(HelpOptionGroup::Target, "sema test build run", "--work-dir", "-wd",
        &cmdLine_->workDir,
        "Set the work directory exposed through @compiler.getBuildCfg().");
    add(HelpOptionGroup::Target, "sema test build run", "--optimize", "-o",
        &cmdLine_->backendOptimize,
        "Enable backend optimization for JIT folding and native code generation.");

    add(HelpOptionGroup::Compiler, "all", "--num-cores", "-j",
        &cmdLine_->numCores,
        "Set the maximum number of CPU cores to use (0 = auto-detect).");
    add(HelpOptionGroup::Compiler, "all", "--stats", "-st",
        &cmdLine_->stats,
        "Display runtime statistics after execution.");
    add(HelpOptionGroup::Compiler, "all", "--stats-mem", "-stm",
        &cmdLine_->statsMem,
        "Display runtime memory statistics after execution.");
    add(HelpOptionGroup::Compiler, "sema test build run", "--tag", nullptr,
        &cmdLine_->tags,
        "Register a compiler tag consumed by #hastag and #gettag. Syntax: Name, Name = value, or Name: type = value.");
    add(HelpOptionGroup::Compiler, "test build run", "--clear-output", "-co",
        &cmdLine_->clear,
        "Clear native work and artifact folders before building native outputs.");

    addEnum<FileSystem::FilePathDisplayMode>(
        HelpOptionGroup::Diagnostics, "all", "--path-display", "-pd",
        &cmdLine_->filePathDisplay,
        {
            {"as-is", FileSystem::FilePathDisplayMode::AsIs},
            {"basename", FileSystem::FilePathDisplayMode::BaseName},
            {"absolute", FileSystem::FilePathDisplayMode::Absolute},
        },
        "Control file path display style for diagnostics, stack traces and file locations.");
    add(HelpOptionGroup::Diagnostics, "all", "--diagnostic-id", "-di",
        &cmdLine_->errorId,
        "Show diagnostic identifiers.");
    add(HelpOptionGroup::Diagnostics, "all", "--diagnostic-one-line", "-dl",
        &cmdLine_->diagOneLine,
        "Display diagnostics as a single line.");

    add(HelpOptionGroup::Logging, "all", "--log-ascii", "-la",
        &cmdLine_->logAscii,
        "Restrict console output to ASCII characters (disable Unicode).");
    add(HelpOptionGroup::Logging, "all", "--log-color", "-lc",
        &cmdLine_->logColor,
        "Enable colored log output for better readability.");
    add(HelpOptionGroup::Logging, "all", "--silent", "-s",
        &cmdLine_->silent,
        "Suppress all log output.");
    add(HelpOptionGroup::Logging, "all", "--syntax-color", "-sc",
        &cmdLine_->syntaxColor,
        "Syntax color output code.");
    add(HelpOptionGroup::Logging, "all", "--syntax-color-lum", "-scl",
        &cmdLine_->syntaxColorLum,
        "Syntax color luminosity factor [0-100].");

    add(HelpOptionGroup::Testing, "test", "--test-native", "-tn",
        &cmdLine_->testNative,
        "Enable native backend testing for #test sources.");
    add(HelpOptionGroup::Testing, "test", "--test-jit", "-tj",
        &cmdLine_->testJit,
        "Enable JIT execution for #test functions during testing.");
    add(HelpOptionGroup::Testing, "test", "--lex-only", nullptr,
        &cmdLine_->lexOnly,
        "Stop test inputs after lexing. Cannot be combined with --syntax-only or --sema-only.");
    add(HelpOptionGroup::Testing, "test", "--syntax-only", nullptr,
        &cmdLine_->syntaxOnly,
        "Stop test inputs after parsing. Cannot be combined with --lex-only or --sema-only.");
    add(HelpOptionGroup::Testing, "test", "--sema-only", nullptr,
        &cmdLine_->semaOnly,
        "Stop test inputs after semantic analysis. Cannot be combined with --lex-only or --syntax-only.");
    add(HelpOptionGroup::Testing, "test", "--output", nullptr,
        &cmdLine_->output,
        "Enable native artifact generation during testing. Use --no-output to keep JIT-only test runs in-memory.");
    add(HelpOptionGroup::Testing, "test", "--verbose-verify", "-vv",
        &cmdLine_->verboseVerify,
        "Show diagnostics normally matched and suppressed by source-driven tests.");
    add(HelpOptionGroup::Testing, "test", "--verbose-verify-filter", "-vvf",
        &cmdLine_->verboseVerifyFilter,
        "Restrict --verbose-verify output to messages or diagnostic IDs matching a specific string.");

    add(HelpOptionGroup::Development, "all", "--dry-run", "-dr",
        &cmdLine_->dryRun,
        "Preview the planned stages, outputs and external commands without executing compile-time code, native tools, tests or emitted artifacts.");
    add(HelpOptionGroup::Development, "all", "--show-config", nullptr,
        &cmdLine_->showConfig,
        "Print computed command, environment, toolchain and native artifact information and exit.");
    add(HelpOptionGroup::Development, "all", "--dev-stop", "-ds",
        &CompilerInstance::dbgDevStop,
        "Open a message box when an error is reported.");
    add(HelpOptionGroup::Development, "all", "--dev-full", "-df",
        &cmdLine_->devFull,
        "Force every compiled development test and validation.");

#if SWC_HAS_UNITTEST
    add(HelpOptionGroup::Development, "all", "--unittest", "-ut",
        &cmdLine_->unittest,
        "Run internal C++ unit tests before executing command.");
    add(HelpOptionGroup::Development, "all", "--verbose-unittest", "-vu",
        &cmdLine_->verboseUnittest,
        "Print each internal unit test status.");
#endif

#if SWC_HAS_VALIDATE_MICRO
    add(HelpOptionGroup::Development, "all", "--validate-micro", nullptr,
        &cmdLine_->validateMicro,
        "Run Micro IR legality and pass-invariant validation.");
#endif

#if SWC_HAS_VALIDATE_NATIVE
    add(HelpOptionGroup::Development, "all", "--validate-native", nullptr,
        &cmdLine_->validateNative,
        "Run native backend validation, including constant relocation validation.");
#endif

#if SWC_DEV_MODE
    add(HelpOptionGroup::Development, "all", "--randomize", "-rz",
        &cmdLine_->randomize,
        "Randomize single-threaded job scheduling. Forces --num-cores=1.");
    add(HelpOptionGroup::Development, "all", "--seed", "-rs",
        &cmdLine_->randSeed,
        "Set the seed for --randomize. Forces --randomize and --num-cores=1.");
#endif
}

SWC_END_NAMESPACE();
