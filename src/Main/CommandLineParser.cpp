#include "pch.h"
#include "Main/CommandLineParser.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"

SWC_BEGIN_NAMESPACE();

constexpr auto   LONG_PREFIX         = "--";
constexpr auto   SHORT_PREFIX        = "-";
constexpr auto   LONG_NO_PREFIX      = "--no-";
constexpr auto   SHORT_NO_PREFIX     = "-no-";
constexpr size_t LONG_PREFIX_LEN     = 2;
constexpr size_t SHORT_PREFIX_LEN    = 1;
constexpr size_t LONG_NO_PREFIX_LEN  = 5;
constexpr size_t SHORT_NO_PREFIX_LEN = 4;

bool CommandLineParser::getNextValue(const Context& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value)
{
    if (index + 1 >= argc)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
        diag.last()->addArgument("arg", arg);
        diag.report(ctx);
        return false;
    }

    value = argv[++index];
    return true;
}

bool CommandLineParser::commandMatches(const Utf8& cmdToCheck, const Utf8& commandList)
{
    if (commandList == "all")
        return true;

    std::istringstream iss(commandList);
    Utf8               cmd;
    while (iss >> cmd)
    {
        if (cmd == cmdToCheck)
            return true;
    }
    return false;
}

bool CommandLineParser::parseEnumString(const Context& ctx, const Utf8& arg, const Utf8& value, const Utf8& enumValues, Utf8* target)
{
    if (enumValues.empty())
    {
        *target = value;
        return true;
    }

    std::istringstream iss(enumValues);
    Utf8               allowed;
    while (std::getline(iss, allowed, '|'))
    {
        if (allowed == value)
        {
            *target = value;
            return true;
        }
    }

    return reportEnumError(ctx, arg, value, enumValues);
}

bool CommandLineParser::parseEnumInt(const Context& ctx, const Utf8& arg, const Utf8& value, const Utf8& enumValues, int* target)
{
    if (enumValues.empty())
    {
        *target = std::stoi(value);
        return true;
    }

    std::istringstream iss(enumValues);
    Utf8               allowed;
    int                index = 0;
    while (std::getline(iss, allowed, '|'))
    {
        if (allowed == value)
        {
            *target = index;
            return true;
        }
        index++;
    }

    return reportEnumError(ctx, arg, value, enumValues);
}

bool CommandLineParser::reportEnumError(const Context& ctx, const Utf8& arg, const Utf8& value, const Utf8& enumValues)
{
    const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidEnumValue);
    diag.last()->addArgument("arg", arg);
    diag.last()->addArgument("value", value);
    diag.last()->addArgument("values", enumValues);
    diag.report(ctx);
    errorRaised_ = true;
    return false;
}

void CommandLineParser::addArg(const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description)
{
    ArgInfo info;
    info.commands    = commands ? commands : "";
    info.longForm    = longForm ? longForm : "";
    info.shortForm   = shortForm ? shortForm : "";
    info.type        = type;
    info.target      = target;
    info.enumValues  = enumValues ? enumValues : "";
    info.description = description ? description : "";

    args_.push_back(info);

    if (!info.longForm.empty())
        longFormMap_[info.longForm] = args_.back();
    if (!info.shortForm.empty())
        shortFormMap_[info.shortForm] = args_.back();
}

const ArgInfo* CommandLineParser::findArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(ctx, arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
        return findShortFormArgument(ctx, arg, invertBoolean);

    return nullptr;
}

const ArgInfo* CommandLineParser::findLongFormArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, LONG_NO_PREFIX_LEN) == LONG_NO_PREFIX && arg.length() > LONG_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, LONG_PREFIX, LONG_NO_PREFIX_LEN, longFormMap_, invertBoolean);
    const auto it = longFormMap_.find(arg);
    return (it != longFormMap_.end()) ? &it->second : nullptr;
}

const ArgInfo* CommandLineParser::findShortFormArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, SHORT_NO_PREFIX_LEN) == SHORT_NO_PREFIX && arg.length() > SHORT_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, SHORT_PREFIX, SHORT_NO_PREFIX_LEN, shortFormMap_, invertBoolean);
    const auto it = shortFormMap_.find(arg);
    return (it != shortFormMap_.end()) ? &it->second : nullptr;
}

const ArgInfo* CommandLineParser::findNegatedArgument(const Context& ctx, const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean)
{
    const Utf8 baseArg = Utf8(prefix) + arg.substr(noPrefixLen);
    const auto it      = argMap.find(baseArg);

    if (it == argMap.end())
    {
        reportInvalidArgument(ctx, arg);
        return nullptr;
    }

    const ArgInfo* info = &it->second;
    if (info->type != CommandLineType::Bool)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidBoolArg);
        diag.last()->addArgument("arg", baseArg);
        diag.report(ctx);
        errorRaised_ = true;
        return nullptr;
    }

    invertBoolean = true;
    return info;
}

void CommandLineParser::reportInvalidArgument(const Context& ctx, const Utf8& arg)
{
    const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidArg);
    diag.last()->addArgument("arg", arg);
    diag.report(ctx);
}

bool CommandLineParser::processArgument(const Context& ctx, const ArgInfo* info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[])
{
    Utf8 value;

    switch (info->type)
    {
        case CommandLineType::Bool:
            *static_cast<bool*>(info->target) = !invertBoolean;
            return true;

        case CommandLineType::Int:
            if (!getNextValue(ctx, arg, index, argc, argv, value))
                return false;
            *static_cast<int*>(info->target) = std::stoi(value);
            return true;

        case CommandLineType::String:
        case CommandLineType::StringPath:
            if (!getNextValue(ctx, arg, index, argc, argv, value))
                return false;
            *static_cast<Utf8*>(info->target) = value;
            return true;

        case CommandLineType::StringSet:
            if (!getNextValue(ctx, arg, index, argc, argv, value))
                return false;
            static_cast<std::set<Utf8>*>(info->target)->insert(value);
            return true;

        case CommandLineType::EnumString:
            if (!getNextValue(ctx, arg, index, argc, argv, value))
                return false;
            return parseEnumString(ctx, arg, value, info->enumValues, static_cast<Utf8*>(info->target));

        case CommandLineType::EnumInt:
            if (!getNextValue(ctx, arg, index, argc, argv, value))
                return false;
            return parseEnumInt(ctx, arg, value, info->enumValues, static_cast<int*>(info->target));
    }

    return false;
}

bool CommandLineParser::parse(int argc, char* argv[])
{
    const CompilerContext context(*cmdLine_, *global_);
    const Context         ctx(context);
    const Utf8            command = "build";

    for (int i = 1; i < argc; i++)
    {
        Utf8 arg           = argv[i];
        bool invertBoolean = false;

        const ArgInfo* info = findArgument(ctx, arg, invertBoolean);
        if (!info)
        {
            if (!errorRaised_)
                reportInvalidArgument(ctx, arg);
            return false;
        }

        if (!commandMatches(command, info->commands))
        {
            const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidArgForCmd);
            diag.last()->addArgument("arg", arg);
            diag.last()->addArgument("command", command);
            diag.report(ctx);
            return false;
        }

        if (!processArgument(ctx, info, arg, invertBoolean, i, argc, argv))
            return false;
    }

    return checkCommandLine();
}

bool CommandLineParser::checkCommandLine() const
{
    if (!cmdLine_->verboseErrorsFilter.empty())
        cmdLine_->verboseErrors = true;
    return true;
}

CommandLineParser::CommandLineParser(CommandLine& cmdLine, Global& global) :
    cmdLine_(&cmdLine),
    global_(&global)
{
    addArg("all", "--silent", nullptr, CommandLineType::Bool, &cmdLine_->silent, nullptr,
           "Suppress all log output.");
    addArg("all", "--stats", nullptr, CommandLineType::Bool, &cmdLine_->stats, nullptr,
           "Display runtime statistics after execution.");
    addArg("all", "--num-cores", nullptr, CommandLineType::Int, &cmdLine_->numCores, nullptr,
           "Set the maximum number of CPU cores to use (0 = auto-detect).");
    addArg("all", "--log-color", nullptr, CommandLineType::Bool, &cmdLine_->logColor, nullptr,
           "Enable colored log output for better readability.");
    addArg("all", "--log-ascii", nullptr, CommandLineType::Bool, &cmdLine_->logAscii, nullptr,
           "Restrict console output to ASCII characters (disable Unicode).");
    addArg("all", "--error-absolute", "-ea", CommandLineType::Bool, &cmdLine_->errorAbsolute, nullptr,
           "Show absolute file paths in error messages.");
    addArg("all", "--verify", "-v", CommandLineType::Bool, &cmdLine_->verify, nullptr,
           "Verify special test annotations or comments.");
    addArg("all", "--verbose-errors", "-ve", CommandLineType::Bool, &cmdLine_->verboseErrors, nullptr,
           "Log raised errors during tests.");
    addArg("all", "--verbose-errors-filter", "-vef", CommandLineType::String, &cmdLine_->verboseErrorsFilter, nullptr,
           "Filter verbose error logs by matching a specific string.");
    addArg("all", "--file-filter", "-ff", CommandLineType::String, &cmdLine_->fileFilter, nullptr,
           "Will only compile files that match the filter.");
    addArg("all", "--file-filter", "-aa", CommandLineType::EnumString, &cmdLine_->fileFilter, "A|B|C",
           "Will only compile files that match the filter.");
}

SWC_END_NAMESPACE();
