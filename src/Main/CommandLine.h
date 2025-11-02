#pragma once
SWC_BEGIN_NAMESPACE()

inline constexpr auto ALLOWED_COMMANDS = "syntax|format";
enum class Command
{
    Syntax  = 0,
    Format  = 1,
    Invalid = -1,
};

struct CommandLine
{
    Command command = Command::Format;

    bool logColor      = true;
    bool logAscii      = false;
    bool errorAbsolute = false;
    bool errorId       = false;
    bool silent        = false;
    bool stats         = false;
    bool dbgDevMode    = false;
    bool verboseErrors = false;
    bool verify        = true;

    uint32_t numCores = 0;
    uint32_t tabSize  = 4;

    Utf8 verboseErrorsFilter;
    Utf8 fileFilter;

    std::set<fs::path> directories;
    std::set<fs::path> files;
};

SWC_END_NAMESPACE()
