#include "pch.h"

#include "CommandLine.h"
#include "CommandLineParser.h"
#include "CompilerContext.h"
#include "CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"

bool CommandLineParser::commandMatches(const Utf8& cmdToCheck, const Utf8& allowedCmds)
{
    if (allowedCmds == "all")
        return true;

    // Split allowedCmds by spaces
    std::istringstream iss(allowedCmds);
    Utf8               cmd;
    while (iss >> cmd)
    {
        if (cmd == cmdToCheck)
            return true;
    }
    return false;
}

bool CommandLineParser::parseEnumString(CompilerContext& ctx, const Utf8& value, const Utf8& enumValues, Utf8* target)
{
    if (enumValues.empty())
    {
        *target = value;
        return true;
    }

    // Check if the value is in the allowed enum values
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

    const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidEnumValue);
    diag.last()->addArgument(value);
    diag.last()->addArgument(enumValues);
    diag.report(ctx);
    return false;
}

bool CommandLineParser::parseEnumInt(CompilerContext& ctx, const Utf8& value, const Utf8& enumValues, int* target)
{
    if (enumValues.empty())
    {
        *target = std::stoi(value);
        return true;
    }

    // Map string to int index
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

    const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidEnumValue);
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

    // Register in maps for a quick lookup
    if (!info.longForm.empty())
        longFormMap_[info.longForm] = args_.back();
    if (!info.shortForm.empty())
        shortFormMap_[info.shortForm] = args_.back();
}

bool CommandLineParser::parse(CompilerContext& ctx, int argc, char* argv[], const Utf8& command)
{
    for (int i = 1; i < argc; i++)
    {
        Utf8 arg = argv[i];

        // Find the argument definition
        const ArgInfo* info = nullptr;
        if (arg.substr(0, 2) == "--")
        {
            auto it = longFormMap_.find(arg);
            if (it != longFormMap_.end())
            {
                info = &it->second;
            }
        }
        else if (arg.substr(0, 1) == "-" && arg.length() > 1)
        {
            auto it = shortFormMap_.find(arg);
            if (it != shortFormMap_.end())
            {
                info = &it->second;
            }
        }

        if (!info)
        {
            const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidArg);
            diag.last()->addArgument(arg);
            diag.report(ctx);
            return false;
        }

        // Check if this argument is valid for the current command
        if (!commandMatches(command, info->commands))
        {
            const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidArgForCmd);
            diag.last()->addArgument(arg);
            diag.last()->addArgument(command);
            diag.report(ctx);
            return false;
        }

        // Parse the value based on type
        switch (info->type)
        {
            case CommandLineType::Bool:
                *static_cast<bool*>(info->target) = true;
                break;

            case CommandLineType::Int:
                if (i + 1 >= argc)
                {
                    const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
                    diag.last()->addArgument(arg);
                    diag.report(ctx);
                    return false;
                }
                *static_cast<int*>(info->target) = std::stoi(argv[++i]);
                break;

            case CommandLineType::String:
            case CommandLineType::StringPath:
                if (i + 1 >= argc)
                {
                    const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
                    diag.last()->addArgument(arg);
                    diag.report(ctx);
                    return false;
                }
                *static_cast<Utf8*>(info->target) = argv[++i];
                break;

            case CommandLineType::StringSet:
                if (i + 1 >= argc)
                {
                    const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
                    diag.last()->addArgument(arg);
                    diag.report(ctx);
                    return false;
                }
                static_cast<std::set<Utf8>*>(info->target)->insert(argv[++i]);
                break;

            case CommandLineType::EnumString:
                if (i + 1 >= argc)
                {
                    const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
                    diag.last()->addArgument(arg);
                    diag.report(ctx);
                    return false;
                }
                if (!parseEnumString(ctx, argv[++i], info->enumValues, static_cast<Utf8*>(info->target)))
                    return false;
                break;

            case CommandLineType::EnumInt:
                if (i + 1 >= argc)
                {
                    const auto diag = Diagnostic::error(DiagnosticId::CmdLineMissingArgValue);
                    diag.last()->addArgument(arg);
                    diag.report(ctx);
                    return false;
                }
                if (!parseEnumInt(ctx, argv[++i], info->enumValues, static_cast<int*>(info->target)))
                    return false;
                break;
        }
    }

    return checkCommandLine(ctx);
}

void CommandLineParser::printHelp(const Utf8& command) const
{
    for (const auto& info : args_)
    {
        if (!commandMatches(command, info.commands))
            continue;
    }
}

bool CommandLineParser::checkCommandLine(const CompilerContext& ctx)
{
    auto &cmdLine = ctx.ci().cmdLine();
    
    if (!cmdLine.verboseErrorsFilter.empty())
        cmdLine.verboseErrors = true;
    
    return true;
}

void CommandLineParser::setupCommandLine(const CompilerContext& ctx)
{
    auto& cmdLine = ctx.ci().cmdLine();
    addArg("all", "--verify", "-v", CommandLineType::Bool, &cmdLine.verify, nullptr, "verify special test comments");
    addArg("all", "--log-color", nullptr, CommandLineType::Bool, &cmdLine.logColor, nullptr, "output to console can be colored");
    addArg("all", "--verbose-errors", "-ve", CommandLineType::Bool, &cmdLine.verboseErrors, nullptr, "log silent errors during tests");
    addArg("all", "--verbose-errors-filter", "-vef", CommandLineType::String, &cmdLine.verboseErrorsFilter, nullptr, "filter log silent errors during tests");
}
