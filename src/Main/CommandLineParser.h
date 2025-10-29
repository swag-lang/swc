#pragma once
SWC_BEGIN_NAMESPACE()
class DiagnosticElement;
;

class Context;
struct CommandLine;
class Global;

// Enum for command line argument types
enum class CommandLineType
{
    Bool,
    Int,
    String,
    Path,
    StringSet,
    PathSet,
    EnumInt,
    EnumString
};

// Internal structure to hold argument metadata
struct ArgInfo
{
    Utf8            commands;  // e.g., "all", "bu sc doc"
    Utf8            longForm;  // e.g., "--silent"
    Utf8            shortForm; // e.g., "-s"
    CommandLineType type;
    void*           target;     // Pointer to the variable to set
    Utf8            enumValues; // For enum types, pipe-separated values
    Utf8            description;

    ArgInfo() :
        type(CommandLineType::Bool),
        target(nullptr)
    {
    }
};

class CommandLineParser
{
    std::vector<ArgInfo>    args_;
    std::map<Utf8, ArgInfo> longFormMap_;
    std::map<Utf8, ArgInfo> shortFormMap_;
    CommandLine*            cmdLine_     = nullptr;
    Global*                 global_      = nullptr;
    bool                    errorRaised_ = false;
    Utf8                    command_;

    static void            printHelp(const Context& ctx);
    static Command         isAllowedCommand(const Utf8& cmd);
    void                   errorArguments(DiagnosticElement& elem, const Utf8& arg);
    void                   errorArguments(DiagnosticElement& elem, const ArgInfo& info, const Utf8& arg);
    bool                   getNextValue(const Context& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value);
    bool                   commandMatches(const Utf8& commandList) const;
    bool                   parseEnumString(const Context& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, Utf8* target);
    bool                   parseEnumInt(const Context& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* target);
    std::optional<ArgInfo> findArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean);
    std::optional<ArgInfo> findLongFormArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean);
    std::optional<ArgInfo> findShortFormArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean);
    std::optional<ArgInfo> findNegatedArgument(const Context& ctx, const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean);
    void                   reportInvalidArgument(const Context& ctx, const Utf8& arg);
    bool                   processArgument(const Context& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[]);
    void                   addArg(const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description);
    bool                   reportEnumError(const Context& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value);
    Result                 checkCommandLine(const Context& ctx) const;

public:
    explicit CommandLineParser(CommandLine& cmdLine, Global& global);
    Result parse(int argc, char* argv[]);
};

SWC_END_NAMESPACE()
