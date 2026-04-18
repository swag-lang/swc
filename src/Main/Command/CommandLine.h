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
    {"syntax", "Check the syntax of the source code without generating any IR or backend code."},
    {"sema", "Perform semantic analysis on the source code, including type checking."},
    {"test", "Run source-driven tests, expected diagnostics, and #test functions."},
    {"build", "Build native artifacts from the input sources without running emitted executables."},
    {"run", "Build native artifacts from the input sources and run emitted executables when available."},
};

enum class CommandKind
{
    Invalid = -1,
    Syntax,
    Sema,
    Test,
    Build,
    Run,
};

struct CommandLine
{
    CommandKind command = CommandKind::Syntax;

    Runtime::TargetOs            targetOs     = Runtime::TargetOs::Windows;
    Runtime::TargetArch          targetArch   = Runtime::TargetArch::X86_64;
    Runtime::BuildCfgBackendKind backendKind  = Runtime::BuildCfgBackendKind::Executable;

#if defined(_M_X64) || defined(__x86_64__)
    Utf8 targetCpu = "x86_64";
#elif defined(_M_IX86) || defined(__i386__)
    Utf8 targetCpu = "x86";
#else
    Utf8 targetCpu = "unknown-cpu";
#endif

    Utf8                buildCfg        = "fast-debug";
    Utf8                name;
    Utf8                moduleNamespace;
    Utf8                moduleNamespaceStorage;
    Utf8                outDirStorage;
    Utf8                workDirStorage;
    std::optional<bool> backendOptimize;

    bool logColor         = true;
    bool logAscii         = false;
    bool syntaxColor      = true;
    bool diagOneLine      = false;
    bool errorId          = false;
    bool silent           = false;
    bool stats            = false;
    bool statsMem         = false;
    bool clear            = false;
    bool dryRun           = false;
    bool showConfig       = false;
    bool verboseVerify      = false;
    bool sourceDrivenTest   = false;
    bool artifactKindExplicit = false;
    bool testNative        = true;
    bool testJit           = true;
    bool lexOnly           = false;
    bool syntaxOnly        = false;
    bool semaOnly          = false;
    bool output            = true;
    bool runtime           = true;

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

    Utf8           verboseVerifyFilter;
    std::set<Utf8> fileFilter;
    std::vector<Utf8> tags;

    std::set<fs::path> directories;
    std::set<fs::path> files;
    std::set<fs::path> originalDirectories;
    std::set<fs::path> originalFiles;

    fs::path          modulePath;
    fs::path          originalModulePath;
    fs::path          outDir;
    fs::path          workDir;
    Runtime::BuildCfg defaultBuildCfg{};

    bool isTestCommand() const noexcept
    {
        return command == CommandKind::Test;
    }

    bool isTestMode() const noexcept
    {
        return sourceDrivenTest || isTestCommand();
    }

    bool isExecutionPreviewOnly() const noexcept
    {
        return dryRun || showConfig;
    }
};

inline const std::set<fs::path>& commandLineInputDirectories(const CommandLine& cmdLine)
{
    if (!cmdLine.originalDirectories.empty())
        return cmdLine.originalDirectories;
    return cmdLine.directories;
}

inline const std::set<fs::path>& commandLineInputFiles(const CommandLine& cmdLine)
{
    if (!cmdLine.originalFiles.empty())
        return cmdLine.originalFiles;
    return cmdLine.files;
}

inline const fs::path& commandLineInputModulePath(const CommandLine& cmdLine)
{
    if (!cmdLine.originalModulePath.empty())
        return cmdLine.originalModulePath;
    return cmdLine.modulePath;
}

inline Utf8 commandLineDefaultArtifactName(const CommandLine& cmdLine)
{
    if (!cmdLine.name.empty())
        return FileSystem::sanitizeFileName(cmdLine.name);

    const auto& modulePath = commandLineInputModulePath(cmdLine);
    if (!modulePath.empty())
        return FileSystem::sanitizeFileName(Utf8(modulePath.filename().string()));

    const auto& files = commandLineInputFiles(cmdLine);
    if (files.size() == 1)
        return FileSystem::sanitizeFileName(Utf8(files.begin()->stem().string()));

    const auto& directories = commandLineInputDirectories(cmdLine);
    if (directories.size() == 1)
        return FileSystem::sanitizeFileName(Utf8(directories.begin()->filename().string()));

    return "native";
}

inline Utf8 commandLineDefaultModuleNamespace(const Utf8& artifactName)
{
    Utf8 result = artifactName;
    if (!result.empty() && result[0] >= 'a' && result[0] <= 'z')
        result[0] = static_cast<char>(result[0] - 'a' + 'A');
    return result;
}

inline Utf8 commandLineTargetArchName(const Runtime::TargetArch targetArch)
{
    switch (targetArch)
    {
        case Runtime::TargetArch::X86_64:
            return "x86_64";
    }

    SWC_UNREACHABLE();
}

inline Utf8 commandLineBackendKindName(const Runtime::BuildCfgBackendKind backendKind)
{
    switch (backendKind)
    {
        case Runtime::BuildCfgBackendKind::Executable:
            return "executable";
        case Runtime::BuildCfgBackendKind::SharedLibrary:
            return "shared-library";
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            return "static-library";
        case Runtime::BuildCfgBackendKind::None:
            return "none";
    }

    SWC_UNREACHABLE();
}

inline Runtime::BuildCfgBackendKind commandLineEffectiveBackendKind(const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind currentKind)
{
    if (cmdLine.artifactKindExplicit)
        return cmdLine.backendKind;
    return currentKind;
}

SWC_END_NAMESPACE();
