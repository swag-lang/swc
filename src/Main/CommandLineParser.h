#pragma once

class CompilerContext;

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

    static bool commandMatches(const Utf8& cmdToCheck, const Utf8& allowedCmds);
    static bool parseEnumString(CompilerContext& ctx, const Utf8& value, const Utf8& enumValues, Utf8* target);
    static bool parseEnumInt(CompilerContext& ctx, const Utf8& value, const Utf8& enumValues, int* target);
    void        addArg(const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description);
    static bool checkCommandLine(const CompilerContext& ctx);

public:
    void setupCommandLine(const CompilerContext& ctx);
    bool parse(CompilerContext& ctx, int argc, char* argv[], const Utf8& command);
    void printHelp(const Utf8& command = "all") const;
};
