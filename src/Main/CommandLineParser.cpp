#include "pch.h"

#include "CommandLine.h"
#include "CommandLineParser.h"
#include "CompilerContext.h"
#include "CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"

constexpr auto   LONG_PREFIX         = "--";
constexpr auto   SHORT_PREFIX        = "-";
constexpr auto   LONG_NO_PREFIX      = "--no-";
constexpr auto   SHORT_NO_PREFIX     = "-no-";
constexpr size_t LONG_PREFIX_LEN     = 2;
constexpr size_t SHORT_PREFIX_LEN    = 1;
constexpr size_t LONG_NO_PREFIX_LEN  = 5;
constexpr size_t SHORT_NO_PREFIX_LEN = 4;

bool CommandLineParser::getNextValue(const Utf8& arg, int& index, int argc, char* argv[], Utf8& value)
{
    if (index + 1 >= argc)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
        diag.last()->addArgument(arg);
        diag.report(ctx_);
        return false;
    }

    value = argv[++index];
    return true;
}

bool CommandLineParser::commandMatches(const Utf8& cmdToCheck, const Utf8& allowedCmds)
{
    if (allowedCmds == "all")
        return true;

    std::istringstream iss(allowedCmds);
    Utf8               cmd;
    while (iss >> cmd)
    {
        if (cmd == cmdToCheck)
            return true;
    }
    return false;
}

bool CommandLineParser::parseEnumString(const Utf8& value, const Utf8& enumValues, Utf8* target)
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

    return reportEnumError(value, enumValues);
}

bool CommandLineParser::parseEnumInt(const Utf8& value, const Utf8& enumValues, int* target)
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

    return reportEnumError(value, enumValues);
}

bool CommandLineParser::reportEnumError(const Utf8& value, const Utf8& enumValues)
{
    CompilerContext ctx;
    const auto      diag = Diagnostic::error(DiagnosticId::CmdLineInvalidEnumValue);
    diag.last()->addArgument(value);
    diag.last()->addArgument(enumValues);
    diag.report(ctx);
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

const ArgInfo* CommandLineParser::findArgument(const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
        return findShortFormArgument(arg, invertBoolean);

    return nullptr;
}

const ArgInfo* CommandLineParser::findLongFormArgument(const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, LONG_NO_PREFIX_LEN) == LONG_NO_PREFIX && arg.length() > LONG_NO_PREFIX_LEN)
        return findNegatedArgument(arg, LONG_PREFIX, LONG_NO_PREFIX_LEN, longFormMap_, invertBoolean);
    const auto it = longFormMap_.find(arg);
    return (it != longFormMap_.end()) ? &it->second : nullptr;
}

const ArgInfo* CommandLineParser::findShortFormArgument(const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, SHORT_NO_PREFIX_LEN) == SHORT_NO_PREFIX && arg.length() > SHORT_NO_PREFIX_LEN)
        return findNegatedArgument(arg, SHORT_PREFIX, SHORT_NO_PREFIX_LEN, shortFormMap_, invertBoolean);
    const auto it = shortFormMap_.find(arg);
    return (it != shortFormMap_.end()) ? &it->second : nullptr;
}

const ArgInfo* CommandLineParser::findNegatedArgument(const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean)
{
    const Utf8 baseArg = Utf8(prefix) + arg.substr(noPrefixLen);
    const auto it      = argMap.find(baseArg);

    if (it == argMap.end())
    {
        reportInvalidArgument(arg);
        return nullptr;
    }

    const ArgInfo* info = &it->second;
    if (info->type != CommandLineType::Bool)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidBoolArg);
        diag.last()->addArgument(arg);
        diag.last()->addArgument(baseArg);
        diag.report(ctx_);
        return nullptr;
    }

    invertBoolean = true;
    return info;
}

void CommandLineParser::reportInvalidArgument(const Utf8& arg)
{
    const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidArg);
    diag.last()->addArgument(arg);
    diag.report(ctx_);
}

bool CommandLineParser::processArgument(const ArgInfo* info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[])
{
    Utf8 value;

    switch (info->type)
    {
        case CommandLineType::Bool:
            *static_cast<bool*>(info->target) = !invertBoolean;
            return true;

        case CommandLineType::Int:
            if (!getNextValue(arg, index, argc, argv, value))
                return false;
            *static_cast<int*>(info->target) = std::stoi(value);
            return true;

        case CommandLineType::String:
        case CommandLineType::StringPath:
            if (!getNextValue(arg, index, argc, argv, value))
                return false;
            *static_cast<Utf8*>(info->target) = value;
            return true;

        case CommandLineType::StringSet:
            if (!getNextValue(arg, index, argc, argv, value))
                return false;
            static_cast<std::set<Utf8>*>(info->target)->insert(value);
            return true;

        case CommandLineType::EnumString:
            if (!getNextValue(arg, index, argc, argv, value))
                return false;
            return parseEnumString(value, info->enumValues, static_cast<Utf8*>(info->target));

        case CommandLineType::EnumInt:
            if (!getNextValue(arg, index, argc, argv, value))
                return false;
            return parseEnumInt(value, info->enumValues, static_cast<int*>(info->target));
    }

    return false;
}

bool CommandLineParser::parse(int argc, char* argv[], const Utf8& command)
{
    for (int i = 1; i < argc; i++)
    {
        Utf8 arg           = argv[i];
        bool invertBoolean = false;

        const ArgInfo* info = findArgument(arg, invertBoolean);
        if (!info)
        {
            reportInvalidArgument(arg);
            return false;
        }

        if (!commandMatches(command, info->commands))
        {
            const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidArgForCmd);
            diag.last()->addArgument(arg);
            diag.last()->addArgument(command);
            diag.report(ctx_);
            return false;
        }

        if (!processArgument(info, arg, invertBoolean, i, argc, argv))
            return false;
    }

    return checkCommandLine();
}

bool CommandLineParser::checkCommandLine()
{
    auto& cmdLine = CompilerInstance::get().cmdLine();

    if (!cmdLine.verboseErrorsFilter.empty())
        cmdLine.verboseErrors = true;

    return true;
}

void CommandLineParser::setupCommandLine()
{
    auto& cmdLine = CompilerInstance::get().cmdLine();
    addArg("all", "--silent", nullptr, CommandLineType::Bool, &cmdLine.silent, nullptr, "no log output");
    addArg("all", "--num-cores", nullptr, CommandLineType::Int, &cmdLine.numCores, nullptr, "maximum number of cpu to use (0 = automatic)");
    addArg("all", "--log-color", nullptr, CommandLineType::Bool, &cmdLine.logColor, nullptr, "log output can be colored");
    addArg("all", "--verify", "-v", CommandLineType::Bool, &cmdLine.verify, nullptr, "verify special test comments");
    addArg("all", "--verbose-errors", "-ve", CommandLineType::Bool, &cmdLine.verboseErrors, nullptr, "log silent errors during tests");
    addArg("all", "--verbose-errors-filter", "-vef", CommandLineType::String, &cmdLine.verboseErrorsFilter, nullptr, "filter logged silent errors during tests");
}
