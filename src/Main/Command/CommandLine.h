#pragma once
#include "Backend/Runtime.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

struct CommandInfo
{
    const char* name;
    const char* description;
};

inline constexpr CommandInfo COMMANDS[] = {
    {"format", "Parse source files and write formatted source back to disk."},
    {"syntax", "Check the syntax of the source code without generating any IR or backend code."},
    {"sema", "Perform semantic analysis on the source code, including type checking."},
    {"test", "Run source-driven tests, expected diagnostics, and #test functions."},
    {"build", "Build native artifacts from the input sources without running emitted executables."},
    {"run", "Build native artifacts from the input sources and run emitted executables when available."},
};

enum class CommandKind
{
    Invalid = -1,
    Format,
    Syntax,
    Sema,
    Test,
    Build,
    Run,
};

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

    bool logColor             = true;
    bool logAscii             = false;
    bool syntaxColor          = true;
    bool diagOneLine          = false;
    bool errorId              = false;
    bool silent               = false;
    bool stats                = false;
    bool statsMem             = false;
    bool clear                = false;
    bool dryRun               = false;
    bool showConfig           = false;
    bool verboseVerify        = false;
    bool sourceDrivenTest     = false;
    bool artifactKindExplicit = false;
    bool commandExplicit      = false;
    bool testNative           = true;
    bool testJit              = true;
    bool lexOnly              = false;
    bool syntaxOnly           = false;
    bool semaOnly             = false;
    bool output               = true;
    bool runtime              = true;

    bool devFull = false;

#if SWC_HAS_UNITTEST
    bool unittest        = true;
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

    fs::path          configFile;
    fs::path          modulePath;
    fs::path          outDir;
    fs::path          workDir;
    Runtime::BuildCfg defaultBuildCfg{};
};

SWC_END_NAMESPACE();
