#pragma once
#include "CompilerContext.h"
#include "Swc.h"

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
    CommandLine&            cmdLine_;
    std::vector<ArgInfo>    args_;
    std::map<Utf8, ArgInfo> longFormMap_;
    std::map<Utf8, ArgInfo> shortFormMap_;
    CompilerContext         ctx_;

    bool           getNextValue(const Utf8& arg, int& index, int argc, char* argv[], Utf8& value);
    bool           commandMatches(const Utf8& cmdToCheck, const Utf8& allowedCmds);
    bool           parseEnumString(const Utf8& value, const Utf8& enumValues, Utf8* target);
    bool           parseEnumInt(const Utf8& value, const Utf8& enumValues, int* target);
    const ArgInfo* findArgument(const Utf8& arg, bool& invertBoolean);
    const ArgInfo* findLongFormArgument(const Utf8& arg, bool& invertBoolean);
    const ArgInfo* findShortFormArgument(const Utf8& arg, bool& invertBoolean);
    const ArgInfo* findNegatedArgument(const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean);
    void           reportInvalidArgument(const Utf8& arg);
    bool           processArgument(const ArgInfo* info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[]);
    void           addArg(const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description);
    bool           reportEnumError(const Utf8& value, const Utf8& enumValues);
    bool           checkCommandLine() const;

public:
    explicit CommandLineParser(Swc& swc) :
        cmdLine_(swc.cmdLine()),
        ctx_(swc)
    {
    }

    void setupCommandLine();
    bool parse(int argc, char* argv[], const Utf8& command);
};
