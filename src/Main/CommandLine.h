#pragma once
SWC_BEGIN_NAMESPACE();

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

    bool     logColor      = true;
    bool     logAscii      = false;
    bool     errorAbsolute = false;
    bool     silent        = false;
    bool     stats         = false;
    uint32_t numCores      = 0;

    uint32_t tabSize = 4;

    bool     verboseErrors = false;
    Utf8     verboseErrorsFilter;
    fs::path folder;
    fs::path file;
    bool     verify = true;
};

SWC_END_NAMESPACE();
