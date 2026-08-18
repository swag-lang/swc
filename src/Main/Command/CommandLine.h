#pragma once
#include "Backend/Runtime.h"
#include "Format/FormatOptions.h"
#include "Main/FileSystem.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"
#include "Support/Report/WarningPolicy.h"

SWC_BEGIN_NAMESPACE();

enum class CommandKind
{
    Invalid = -1,
    New,
    Clean,
    Format,
    Syntax,
    Sema,
    Doc,
    Unittest,
    Test,
    Smoke,
    Build,
    Run,
};

enum class NewProjectKind
{
    Invalid,
    Script,
    Module,
};

struct CommandInfo
{
    CommandKind kind;
    const char* name;
    const char* description;
};

inline constexpr CommandInfo COMMANDS[] = {
    {CommandKind::New, "new", "Create a runnable script or an executable workspace module"},
    {CommandKind::Clean, "clean", "Remove what a build produced, and the caches the compiler keeps between runs"},
    {CommandKind::Format, "format", "Parse source files and write their canonical formatting back to disk"},
    {CommandKind::Syntax, "syntax", "Check source syntax without generating IR or backend code"},
    {CommandKind::Sema, "sema", "Analyze source semantics, including type checking"},
    {CommandKind::Doc, "doc", "Compile source semantics and generate HTML documentation"},
#if SWC_HAS_UNITTEST
    {CommandKind::Unittest, "unittest", "Run only the internal C++ unit tests"},
#endif
    {CommandKind::Test, "test", "Run source-driven tests, expected diagnostics, and #test functions"},
    {CommandKind::Smoke, "smoke", "Run emitted executables for a bounded number of frames, isolated from the machine, to prove they start and run"},
    {CommandKind::Build, "build", "Build native artifacts from input sources without running emitted executables"},
    {CommandKind::Run, "run", "Build native artifacts from input sources and run emitted executables when available"},
};

inline constexpr std::string_view SWAG_TEST_RUN_ARG = "swag.test";

// Asks the runtime to isolate the generated executable from real machine state before any
// user code runs. Without a value the process picks its own private root; the runtime does
// the work, so nothing here has to know where that ends up.
inline constexpr std::string_view SWAG_SANDBOX_RUN_ARG = "swag.sandbox";

// Grants the isolated process one directory outside its sandbox that stays writable: the
// sources whose tests are running. A test keeps its reference data next to itself, so this
// is what lets a snapshot be recorded without giving the run the machine back.
inline constexpr std::string_view SWAG_SANDBOX_CORPUS_RUN_ARG = "swag.sandbox.corpus";

// Bounds a smoke run: the program stops after this many rendered frames. Carried as
// 'swag.smoke=<frames>' so the budget belongs to the launcher, not to each application.
inline constexpr std::string_view SWAG_SMOKE_RUN_ARG = "swag.smoke";

// Frames a smoke run renders before it stops, when the command line does not say.
inline constexpr uint32_t SWAG_SMOKE_DEFAULT_FRAMES = 50;

// Seconds a bounded run may take before it is killed. Generous enough for the slowest module
// in the tree, small enough that a stuck program fails a suite instead of hanging it.
inline constexpr uint32_t SWAG_RUN_DEFAULT_TIMEOUT_SECONDS = 300;

inline Runtime::CompilerCommand compilerCommandFromKind(const CommandKind command)
{
    switch (command)
    {
        case CommandKind::New:
            return Runtime::CompilerCommand::Build;
        case CommandKind::Test:
            return Runtime::CompilerCommand::Test;
        case CommandKind::Format:
            return Runtime::CompilerCommand::Format;
        case CommandKind::Syntax:
        case CommandKind::Sema:
        case CommandKind::Doc:
        case CommandKind::Unittest:
        case CommandKind::Build:
        case CommandKind::Run:
        // A smoke run compiles the program as it ships: it proves the real thing starts, so
        // '#test' bodies stay out of it.
        case CommandKind::Smoke:
            return Runtime::CompilerCommand::Build;
        default:
            SWC_UNREACHABLE();
    }
}

// Reports whether the command builds artifacts and then runs the emitted executable.
inline bool isRunLikeCommand(const CommandKind command)
{
    return command == CommandKind::Run || command == CommandKind::Smoke;
}

inline bool hasRunArg(const std::vector<Utf8>& runArgs, const std::string_view value)
{
    for (const Utf8& arg : runArgs)
    {
        if (arg.view() == value)
            return true;
    }

    return false;
}

// Reports whether a run argument named `name` is present, on its own or carrying a value as
// 'name=value'. A caller that pinned its own sandbox root must not be given a second marker.
inline bool hasRunArgNamed(const std::vector<Utf8>& runArgs, const std::string_view name)
{
    for (const Utf8& arg : runArgs)
    {
        const std::string_view view = arg.view();
        if (view == name)
            return true;
        if (view.size() > name.size() && view.starts_with(name) && view[name.size()] == '=')
            return true;
    }

    return false;
}

struct CommandLine
{
    CommandKind command = CommandKind::Syntax;

    Runtime::TargetOs                    targetOs     = Runtime::TargetOs::Windows;
    Runtime::TargetArch                  targetArch   = Runtime::TargetArch::X86_64;
    Runtime::BuildCfgBackendKind         backendKind  = Runtime::BuildCfgBackendKind::Executable;
    Runtime::BuildCfgBackendCpuVectorize cpuVectorize = Runtime::BuildCfgBackendCpuVectorize::None;
    FormatNamedStyle                     formatStyle  = FormatNamedStyle::Swag;

#if defined(_M_X64) || defined(__x86_64__)
    Utf8 targetCpu = "x86_64";
#elif defined(_M_IX86) || defined(__i386__)
    Utf8 targetCpu = "x86";
#else
    Utf8 targetCpu = "unknown-cpu";
#endif

    Utf8                buildCfg = "fast-debug";
    Utf8                name;
    Utf8                newProjectName;
    Utf8                moduleNamespace;
    Utf8                workspaceModuleFilter;
    Utf8                moduleNamespaceStorage;
    Utf8                outDirStorage;
    Utf8                workDirStorage;
    std::optional<bool> backendOptimize;

    bool logColor                = true;
    bool logAscii                = false;
    bool logProgress             = true;
    bool syntaxColor             = true;
    bool diagOneLine             = false;
    bool errorId                 = false;
    bool silent                  = false;
    bool stats                   = false;
    bool statsMem                = false;
    bool publish                 = false;
    bool cleanCache              = false;
    bool rebuild                 = false;
    bool dryRun                  = false;
    bool showConfig              = false;
    bool dumpFormatConfig        = false;
    bool helpPrinted             = false;
    bool verboseVerify           = false;
    bool scriptMode              = false;
    bool sourceDrivenTest        = false;
    bool buildCfgExplicit        = false;
    bool artifactKindExplicit    = false;
    bool cpuVectorizeExplicit    = false;
    bool artifactNameExplicit    = false;
    bool moduleNamespaceExplicit = false;
    bool outDirExplicit          = false;
    bool workDirExplicit         = false;
    bool commandExplicit         = false;
    bool testNative              = true;
    bool testJit                 = true;
    bool lexOnly                 = false;
    bool syntaxOnly              = false;
    bool semaOnly                = false;
    bool output                  = true;
    bool outputDoc               = true;
    bool devStopDiagnostics      = true;

    bool devFull = false;

#if SWC_HAS_UNITTEST
    bool verboseUnittest = false;
#endif

#if SWC_HAS_VALIDATE_MICRO
    bool validateMicro = false;
#endif

#if SWC_HAS_VALIDATE_NATIVE
    bool validateNative = false;
#endif

#if SWC_DEV_MODE
    bool     randomize = false;
    uint32_t randSeed  = 0;
#endif

    // Days a dependency copy may go unused before 'clean --cache' takes it; zero removes them all.
    uint32_t cleanCacheDays = 0;

    uint32_t                        syntaxColorLum  = 0;
    uint32_t                        numCores        = 0;
    uint32_t                        tabSize         = 4;
    uint32_t                        diagMaxColumn   = 120;
    FileSystem::FilePathDisplayMode filePathDisplay = FileSystem::FilePathDisplayMode::Absolute;

    Utf8              verboseVerifyFilter;
    Utf8              docCss;
    std::set<Utf8>    fileFilter;
    std::set<Utf8>    testFileFilter;
    std::vector<Utf8> tags;
    std::vector<Utf8> runArgs;

    // Raw '--warn-*' values, in the order the options accept them. They become
    // 'warningPolicy' once the command line is fully parsed and validated.
    std::vector<Utf8> warnAsErrors;
    std::vector<Utf8> warnAsWarnings;
    std::vector<Utf8> warnDisabled;
    WarningPolicy     warningPolicy;

    // Frames a smoke run renders before stopping.
    uint32_t smokeFrames = SWAG_SMOKE_DEFAULT_FRAMES;

    // Seconds a bounded run (test or smoke) may take before it is killed and reported failed.
    uint32_t runTimeoutSeconds = SWAG_RUN_DEFAULT_TIMEOUT_SECONDS;

    std::set<fs::path> directories;
    std::set<fs::path> files;
    std::set<Utf8>     importApiModules;
    std::set<fs::path> importApiDirs;
    std::set<fs::path> importApiFiles;

    fs::path          configFile;
    fs::path          newScriptPath;
    fs::path          moduleFilePath;
    fs::path          modulePath;
    fs::path          workspacePath;
    fs::path          exportApiDir;
    fs::path          docOutputDir;
    fs::path          outDir;
    fs::path          workDir;
    Runtime::BuildCfg defaultBuildCfg{};
    NewProjectKind    newProjectKind = NewProjectKind::Invalid;
};

constexpr std::string_view commandName(const CommandKind command)
{
    switch (command)
    {
        case CommandKind::New:
            return "new";
        case CommandKind::Clean:
            return "clean";
        case CommandKind::Format:
            return "format";
        case CommandKind::Syntax:
            return "syntax";
        case CommandKind::Sema:
            return "sema";
        case CommandKind::Doc:
            return "doc";
        case CommandKind::Unittest:
            return "unittest";
        case CommandKind::Test:
            return "test";
        case CommandKind::Smoke:
            return "smoke";
        case CommandKind::Build:
            return "build";
        case CommandKind::Run:
            return "run";
        case CommandKind::Invalid:
            return "unavailable";
    }

    SWC_UNREACHABLE();
}

// Suffix carried by every file a build emits, so two commands that turn the same
// sources into different programs can never share one.
//
// A test build is not the same program as a normal build of the same module: it
// compiles `#test` bodies in, answers `#command` with `Test` so the source can
// select different constants, and forces debug info and exceptions on. Without a
// distinct name the two overwrite each other's executable, PDB, and object files,
// and `run` happily launches whichever was built last. A focused test gets a third
// name because its executable deliberately omits the unselected test entry points.
inline std::string_view artifactModeSuffix(const CommandLine& cmdLine)
{
    if (!cmdLine.sourceDrivenTest)
        return "";
    if (!cmdLine.testFileFilter.empty())
        return ".test.focused";
    return ".test";
}

inline std::vector<Utf8> effectiveGeneratedArtifactRunArgs(const CommandLine& cmdLine)
{
    std::vector<Utf8> result = cmdLine.runArgs;
    if (cmdLine.command == CommandKind::Test && !hasRunArg(result, SWAG_TEST_RUN_ARG))
        result.emplace_back(SWAG_TEST_RUN_ARG);

    // A smoke run is the real program, bounded. The frame budget travels with it so no
    // application has to recognize that it is being exercised.
    if (cmdLine.command == CommandKind::Smoke && !hasRunArgNamed(result, SWAG_SMOKE_RUN_ARG))
    {
        result.emplace_back(std::format("{}={}", SWAG_SMOKE_RUN_ARG, cmdLine.smokeFrames));
    }

    // Neither a test nor a smoke run may reach the machine it runs on. Isolation is imposed
    // here, on the command, so it cannot depend on a module remembering to ask for it.
    if ((cmdLine.command == CommandKind::Test || cmdLine.command == CommandKind::Smoke) &&
        !hasRunArgNamed(result, SWAG_SANDBOX_RUN_ARG))
    {
        result.emplace_back(SWAG_SANDBOX_RUN_ARG);
    }

    // A test records its reference data beside the source that produces it, which the sandbox
    // refuses like any other write outside itself. The sources under test are granted back, and
    // only them, so recording a snapshot stays possible while the machine does not. A smoke run
    // records nothing and is granted nothing.
    if (cmdLine.command == CommandKind::Test && !hasRunArgNamed(result, SWAG_SANDBOX_CORPUS_RUN_ARG))
    {
        const fs::path& corpus = cmdLine.modulePath.empty() ? cmdLine.workspacePath : cmdLine.modulePath;
        if (!corpus.empty())
            result.emplace_back(std::format("{}={}", SWAG_SANDBOX_CORPUS_RUN_ARG, corpus.string()));
    }

    return result;
}

SWC_END_NAMESPACE();
