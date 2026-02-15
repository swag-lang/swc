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

struct CommandLine
{
    CommandKind command = CommandKind::Syntax;

    Runtime::TargetOs targetOs = Runtime::TargetOs::Windows;

    bool logColor                 = true;
    bool logAscii                 = false;
    bool syntaxColor              = true;
    bool diagAbsolute             = false;
    bool diagOneLine              = false;
    bool errorId                  = false;
    bool silent                   = false;
    bool stats                    = false;
    bool verboseVerify            = false;
    bool verboseHardwareException = false;
    bool verify                   = true;
    bool debugInfo                = false;
    bool internalUnittest         = true;
    bool verboseInternalUnittest  = false;
    bool runtime                  = false;

    static inline bool dbgDevMode = false;

#ifdef SWC_DEV_MODE
    bool     randomize = false;
    uint32_t randSeed  = 0;
#endif

    uint32_t syntaxColorLum = 0;
    uint32_t numCores       = 0;
    uint32_t tabSize        = 4;
    uint32_t diagMaxColumn  = 120;

    Utf8           verboseVerifyFilter;
    std::set<Utf8> fileFilter;

    std::set<fs::path> directories;
    std::set<fs::path> files;

    fs::path modulePath;
};

SWC_END_NAMESPACE();
