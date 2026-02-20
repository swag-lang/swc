#pragma once
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

struct CommandInfo
{
    const char* name;
    const char* description;
};

inline constexpr CommandInfo COMMANDS[] = {
    {"syntax", "Check the syntax of the source code without generating any IR or backend code."},
    {"sema", "Perform semantic analysis on the source code, including type checking."},
};
enum class CommandKind
{
    Syntax,
    Sema,
    Invalid = -1,
};

enum class FilePathDisplayMode : uint8_t
{
    AsIs,
    BaseName,
    Absolute,
};

struct CommandLine
{
    CommandKind command = CommandKind::Syntax;

    Runtime::TargetOs   targetOs   = Runtime::TargetOs::Windows;
    Runtime::TargetArch targetArch = Runtime::TargetArch::X86_64;

#if defined(_M_X64) || defined(__x86_64__)
    Utf8 targetCpu = "x86_64";
#elif defined(_M_IX86) || defined(__i386__)
    Utf8 targetCpu = "x86";
#else
    Utf8 targetCpu = "unknown-cpu";
#endif

    Utf8 buildCfg       = "fast-debug";
    Utf8 targetArchName = "x86_64";

    bool logColor                = true;
    bool logAscii                = false;
    bool syntaxColor             = true;
    bool diagOneLine             = false;
    bool errorId                 = false;
    bool silent                  = false;
    bool stats                   = false;
    bool verboseVerify           = false;
    bool verify                  = true;
    bool debugInfo               = false;
    bool internalUnittest        = true;
    bool verboseInternalUnittest = false;
    bool runtime                 = false;

    static inline bool dbgDevMode = false;

#ifdef SWC_DEV_MODE
    bool     randomize = false;
    uint32_t randSeed  = 0;
#endif

    uint32_t syntaxColorLum  = 0;
    uint32_t numCores        = 0;
    uint32_t tabSize         = 4;
    uint32_t diagMaxColumn   = 120;
    int      filePathDisplay = static_cast<int>(FilePathDisplayMode::BaseName);

    Utf8           verboseVerifyFilter;
    std::set<Utf8> fileFilter;

    std::set<fs::path> directories;
    std::set<fs::path> files;

    fs::path modulePath;

    FilePathDisplayMode filePathDisplayMode() const
    {
        switch (filePathDisplay)
        {
            case static_cast<int>(FilePathDisplayMode::AsIs):
                return FilePathDisplayMode::AsIs;
            case static_cast<int>(FilePathDisplayMode::BaseName):
                return FilePathDisplayMode::BaseName;
            case static_cast<int>(FilePathDisplayMode::Absolute):
                return FilePathDisplayMode::Absolute;
            default:
                return FilePathDisplayMode::BaseName;
        }
    }
};

SWC_END_NAMESPACE();
