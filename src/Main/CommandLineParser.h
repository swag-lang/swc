#pragma once
SWC_BEGIN_NAMESPACE()

class EvalContext;
struct CommandLine;
class Global;

// Enum for command line argument types
enum class CommandLineType
{
    Bool,
    Int,
    String,
    StringPath,
    StringSet,
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
    CommandLine*            cmdLine_ = nullptr;
    Global*                 global_  = nullptr;

    static bool           getNextValue(EvalContext& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value);
    static bool           commandMatches(const Utf8& cmdToCheck, const Utf8& commandList);
    static bool           parseEnumString(EvalContext& ctx, const Utf8& value, const Utf8& enumValues, Utf8* target);
    static bool           parseEnumInt(EvalContext& ctx, const Utf8& value, const Utf8& enumValues, int* target);
    const ArgInfo*        findArgument(EvalContext& ctx, const Utf8& arg, bool& invertBoolean);
    const ArgInfo*        findLongFormArgument(EvalContext& ctx, const Utf8& arg, bool& invertBoolean);
    const ArgInfo*        findShortFormArgument(EvalContext& ctx, const Utf8& arg, bool& invertBoolean);
    static const ArgInfo* findNegatedArgument(EvalContext& ctx, const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean);
    static void           reportInvalidArgument(EvalContext& ctx, const Utf8& arg);
    static bool           processArgument(EvalContext& ctx, const ArgInfo* info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[]);
    void                  addArg(const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description);
    static bool           reportEnumError(EvalContext& ctx, const Utf8& value, const Utf8& enumValues);
    bool                  checkCommandLine() const;

public:
    explicit CommandLineParser(CommandLine& cmdLine, Global& global);
    bool parse(int argc, char* argv[]);
};

SWC_END_NAMESPACE()
