#pragma once
#include "Backend/Runtime.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

enum class CommandKind
{
    Invalid = -1,
    Format,
    Syntax,
    Sema,
    Unittest,
    Test,
    Build,
    Run,
};

struct CommandInfo
{
    CommandKind kind;
    const char* name;
    const char* description;
};

inline constexpr CommandInfo COMMANDS[] = {
    {CommandKind::Format, "format", "Parse source files and write formatted source back to disk."},
    {CommandKind::Syntax, "syntax", "Check the syntax of the source code without generating any IR or backend code."},
    {CommandKind::Sema, "sema", "Perform semantic analysis on the source code, including type checking."},
#if SWC_HAS_UNITTEST
    {CommandKind::Unittest, "unittest", "Run internal C++ unit tests only."},
#endif
    {CommandKind::Test, "test", "Run source-driven tests, expected diagnostics, and #test functions."},
    {CommandKind::Build, "build", "Build native artifacts from the input sources without running emitted executables."},
    {CommandKind::Run, "run", "Build native artifacts from the input sources and run emitted executables when available."},
};

inline Runtime::CompilerCommand compilerCommandFromKind(const CommandKind command)
{
    switch (command)
    {
        case CommandKind::Test:
            return Runtime::CompilerCommand::Test;
        case CommandKind::Format:
            return Runtime::CompilerCommand::Format;
        case CommandKind::Syntax:
        case CommandKind::Sema:
        case CommandKind::Unittest:
        case CommandKind::Build:
        case CommandKind::Run:
            return Runtime::CompilerCommand::Build;
        default:
            SWC_UNREACHABLE();
    }
}

struct CommandLine
{
    CommandKind command = CommandKind::Syntax;

    Runtime::TargetOs            targetOs    = Runtime::TargetOs::Windows;
    Runtime::TargetArch          targetArch  = Runtime::TargetArch::X86_64;
    Runtime::BuildCfgBackendKind backendKind = Runtime::BuildCfgBackendKind::Executable;

#if defined(_M_X64) || defined(__x86_64__)
    Utf8 targetCpu = "x86_64";
#elif defined(_M_IX86) || defined(__i386__)
    Utf8 targetCpu = "x86";
#else
    Utf8 targetCpu = "unknown-cpu";
#endif

    Utf8                buildCfg = "fast-debug";
    Utf8                name;
    Utf8                moduleNamespace;
    Utf8                moduleNamespaceStorage;
    Utf8                outDirStorage;
    Utf8                workDirStorage;
    std::optional<bool> backendOptimize;

    bool logColor                = true;
    bool logAscii                = false;
    bool syntaxColor             = true;
    bool diagOneLine             = false;
    bool errorId                 = false;
    bool silent                  = false;
    bool stats                   = false;
    bool statsMem                = false;
    bool clear                   = false;
    bool dryRun                  = false;
    bool showConfig              = false;
    bool verboseVerify           = false;
    bool sourceDrivenTest        = false;
    bool buildCfgExplicit        = false;
    bool artifactKindExplicit    = false;
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
    bool runtime                 = true;
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

    uint32_t                        syntaxColorLum  = 0;
    uint32_t                        numCores        = 0;
    uint32_t                        tabSize         = 4;
    uint32_t                        diagMaxColumn   = 120;
    FileSystem::FilePathDisplayMode filePathDisplay = FileSystem::FilePathDisplayMode::Absolute;

    Utf8              verboseVerifyFilter;
    std::set<Utf8>    fileFilter;
    std::vector<Utf8> tags;

    std::set<fs::path> directories;
    std::set<fs::path> files;
    std::set<Utf8>     importApiModules;
    std::set<fs::path> importApiDirs;
    std::set<fs::path> importApiFiles;

    fs::path          configFile;
    fs::path          moduleFilePath;
    fs::path          modulePath;
    fs::path          workspacePath;
    fs::path          exportApiDir;
    fs::path          outDir;
    fs::path          workDir;
    Runtime::BuildCfg defaultBuildCfg{};
};

constexpr std::string_view commandName(const CommandKind command)
{
    switch (command)
    {
        case CommandKind::Format:
            return "format";
        case CommandKind::Syntax:
            return "syntax";
        case CommandKind::Sema:
            return "sema";
        case CommandKind::Unittest:
            return "unittest";
        case CommandKind::Test:
            return "test";
        case CommandKind::Build:
            return "build";
        case CommandKind::Run:
            return "run";
        case CommandKind::Invalid:
            return "invalid";
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
