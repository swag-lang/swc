#pragma once

SWC_BEGIN_NAMESPACE()

class Diagnostic;
class TaskContext;
struct CommandLine;
class Global;
enum class CommandKind;

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
public:
    explicit CommandLineParser(Global& global, CommandLine& cmdLine);
    AstStepResult parse(int argc, char* argv[]);

private:
    std::vector<ArgInfo>    args_;
    std::map<Utf8, ArgInfo> longFormMap_;
    std::map<Utf8, ArgInfo> shortFormMap_;
    CommandLine*            cmdLine_     = nullptr;
    Global*                 global_      = nullptr;
    bool                    errorRaised_ = false;
    Utf8                    command_;

    static void            printHelp(const TaskContext& ctx);
    static CommandKind     isAllowedCommand(const Utf8& cmd);
    void                   setReportArguments(Diagnostic& diag, const Utf8& arg);
    void                   setReportArguments(Diagnostic& diag, const ArgInfo& info, const Utf8& arg);
    bool                   getNextValue(TaskContext& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value);
    bool                   commandMatches(const Utf8& commandList) const;
    bool                   parseEnumString(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, Utf8* target);
    bool                   parseEnumInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* target);
    std::optional<ArgInfo> findArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean);
    std::optional<ArgInfo> findLongFormArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean);
    std::optional<ArgInfo> findShortFormArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean);
    std::optional<ArgInfo> findNegatedArgument(TaskContext& ctx, const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean);
    void                   reportInvalidArgument(TaskContext& ctx, const Utf8& arg);
    bool                   processArgument(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[]);
    void                   addArg(const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description);
    bool                   reportEnumError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value);
    AstStepResult                 checkCommandLine(TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
