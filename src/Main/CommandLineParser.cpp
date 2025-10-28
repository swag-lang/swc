#include "pch.h"

#include "FileSystem.h"
#include "Global.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/Context.h"
#include "Main/Version.h"
#include "Report/Diagnostic.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE();

constexpr auto   LONG_PREFIX         = "--";
constexpr auto   SHORT_PREFIX        = "-";
constexpr auto   LONG_NO_PREFIX      = "--no-";
constexpr auto   SHORT_NO_PREFIX     = "-no-";
constexpr size_t LONG_PREFIX_LEN     = 2;
constexpr size_t SHORT_PREFIX_LEN    = 1;
constexpr size_t LONG_NO_PREFIX_LEN  = 5;
constexpr size_t SHORT_NO_PREFIX_LEN = 4;

// Pipe-delimited list of allowed command names.
// Adjust to match your tool's commands.
Command CommandLineParser::isAllowedCommand(const Utf8& cmd)
{
    const Utf8         ac = ALLOWED_COMMANDS;
    std::istringstream iss(ac);

    Utf8 allowed;
    int  index = 0;
    while (std::getline(iss, allowed, '|'))
    {
        if (allowed == cmd)
            return static_cast<Command>(index);
        index++;
    }

    return Command::Invalid;
}

void CommandLineParser::errorArguments(DiagnosticElement& elem, const Utf8& arg)
{
    elem.addArgument(Diagnostic::ARG_ARG, arg);
    elem.addArgument(Diagnostic::ARG_COMMAND, command_);
    errorRaised_ = true;
}

void CommandLineParser::errorArguments(DiagnosticElement& elem, const ArgInfo& info, const Utf8& arg)
{
    errorArguments(elem, arg);
    elem.addArgument(Diagnostic::ARG_ARG, arg);
    elem.addArgument(Diagnostic::ARG_COMMAND, command_);
    elem.addArgument(Diagnostic::ARG_LONG, info.longForm);
    elem.addArgument(Diagnostic::ARG_SHORT, info.shortForm);
    elem.addArgument(Diagnostic::ARG_VALUES, info.enumValues);
    errorRaised_ = true;
}

bool CommandLineParser::getNextValue(const Context& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value)
{
    if (index + 1 >= argc)
    {
        const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineMissingArgValue);
        errorArguments(diag.last(), arg);
        return false;
    }

    value = argv[++index];
    return true;
}

bool CommandLineParser::commandMatches(const Utf8& commandList) const
{
    if (commandList == "all")
        return true;

    std::istringstream iss(commandList);
    Utf8               cmd;
    while (iss >> cmd)
    {
        if (cmd == command_)
            return true;
    }
    return false;
}

bool CommandLineParser::parseEnumString(const Context& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, Utf8* target)
{
    if (info.enumValues.empty())
    {
        *target = value;
        return true;
    }

    std::istringstream iss(info.enumValues);
    Utf8               allowed;
    while (std::getline(iss, allowed, '|'))
    {
        if (allowed == value)
        {
            *target = value;
            return true;
        }
    }

    return reportEnumError(ctx, info, arg, value);
}

bool CommandLineParser::parseEnumInt(const Context& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* target)
{
    if (info.enumValues.empty())
    {
        *target = std::stoi(value);
        return true;
    }

    std::istringstream iss(info.enumValues);
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

    return reportEnumError(ctx, info, arg, value);
}

bool CommandLineParser::reportEnumError(const Context& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value)
{
    const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineInvalidEnumValue);
    errorArguments(diag.last(), info, arg);
    diag.last().addArgument("value", value);
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

std::optional<ArgInfo> CommandLineParser::findArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(ctx, arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
        return findShortFormArgument(ctx, arg, invertBoolean);

    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findLongFormArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, LONG_NO_PREFIX_LEN) == LONG_NO_PREFIX && arg.length() > LONG_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, LONG_PREFIX, LONG_NO_PREFIX_LEN, longFormMap_, invertBoolean);
    const auto it = longFormMap_.find(arg);
    if (it != longFormMap_.end())
        return it->second;
    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findShortFormArgument(const Context& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, SHORT_NO_PREFIX_LEN) == SHORT_NO_PREFIX && arg.length() > SHORT_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, SHORT_PREFIX, SHORT_NO_PREFIX_LEN, shortFormMap_, invertBoolean);
    const auto it = shortFormMap_.find(arg);
    if (it != shortFormMap_.end())
        return it->second;
    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findNegatedArgument(const Context& ctx, const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean)
{
    const Utf8 baseArg = Utf8(prefix) + arg.substr(noPrefixLen);
    const auto it      = argMap.find(baseArg);

    if (it == argMap.end())
    {
        reportInvalidArgument(ctx, arg);
        return std::nullopt;
    }

    const ArgInfo& info = it->second;
    if (info.type != CommandLineType::Bool)
    {
        const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineInvalidBoolArg);
        errorArguments(diag.last(), info, arg);
        return std::nullopt;
    }

    invertBoolean = true;
    return info;
}

void CommandLineParser::reportInvalidArgument(const Context& ctx, const Utf8& arg)
{
    const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineInvalidArg);
    errorArguments(diag.last(), arg);
}

bool CommandLineParser::processArgument(const Context& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[])
{
    Utf8 value;

    switch (info.type)
    {
    case CommandLineType::Bool:
        *static_cast<bool*>(info.target) = !invertBoolean;
        return true;

    case CommandLineType::Int:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        *static_cast<int*>(info.target) = std::stoi(value);
        return true;

    case CommandLineType::String:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        *static_cast<Utf8*>(info.target) = value;
        return true;

    case CommandLineType::Path:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        *static_cast<fs::path*>(info.target) = value.c_str();
        return true;

    case CommandLineType::StringSet:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        static_cast<std::set<Utf8>*>(info.target)->insert(value);
        return true;

    case CommandLineType::PathSet:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        static_cast<std::set<fs::path>*>(info.target)->insert(value.c_str());
        return true;

    case CommandLineType::EnumString:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        return parseEnumString(ctx, info, arg, value, static_cast<Utf8*>(info.target));

    case CommandLineType::EnumInt:
        if (!getNextValue(ctx, arg, index, argc, argv, value))
            return false;
        return parseEnumInt(ctx, info, arg, value, static_cast<int*>(info.target));
    }

    return false;
}

void CommandLineParser::printHelp(const Context& ctx)
{
    ctx.global().logger().lock();
    Logger::printDim(ctx, std::format("swag version {}.{}.{}\n", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
    Logger::printDim(ctx, "Usage:\n");
    Logger::printDim(ctx, "    swag <command> [options]\n");
    ctx.global().logger().unlock();
}

Result CommandLineParser::parse(int argc, char* argv[])
{
    const CompilerContext context(*cmdLine_, *global_);
    const Context         ctx(context);

    if (argc == 1)
    {
        printHelp(ctx);
        return Result::Error;
    }

    // Require a command as the first positional token (no leading '-').
    if (argc <= 1 || argv[1][0] == '-')
    {
        // Missing command name
        const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineMissingCommand);
        return Result::Error;
    }

    // Validate and set the command
    {
        const Utf8 candidate = argv[1];
        cmdLine_->command    = isAllowedCommand(candidate);
        if (cmdLine_->command == Command::Invalid)
        {
            const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineInvalidCommand);
            errorArguments(diag.last(), argv[1]);
            diag.last().addArgument(Diagnostic::ARG_VALUES, ALLOWED_COMMANDS);
            return Result::Error;
        }

        command_ = candidate;
    }

    for (int i = 2; i < argc; i++)
    {
        Utf8 arg           = argv[i];
        bool invertBoolean = false;

        const auto info = findArgument(ctx, arg, invertBoolean);
        if (!info)
        {
            if (!errorRaised_)
                reportInvalidArgument(ctx, arg);
            return Result::Error;
        }

        if (!commandMatches(info.value().commands))
        {
            const auto diag = Diagnostic::raise(ctx, DiagnosticId::CmdLineInvalidArgForCmd);
            errorArguments(diag.last(), info.value(), arg);
            return Result::Error;
        }

        if (!processArgument(ctx, info.value(), arg, invertBoolean, i, argc, argv))
            return Result::Error;
    }

    return checkCommandLine(ctx);
}

Result CommandLineParser::checkCommandLine(const Context& ctx) const
{
    if (!cmdLine_->verboseErrorsFilter.empty())
        cmdLine_->verboseErrors = true;

    // Resolve all folders
    std::set<fs::path> resolvedFolders;
    for (const auto& folder : cmdLine_->directories)
    {
        fs::path temp = folder;
        SWC_CHECK(FileSystem::resolveFolder(ctx, temp));
        resolvedFolders.insert(std::move(temp));
    }
    cmdLine_->directories = std::move(resolvedFolders);

    // Resolve all files
    std::set<fs::path> resolvedFiles;
    for (const auto& file : cmdLine_->files)
    {
        fs::path temp = file;
        SWC_CHECK(FileSystem::resolveFile(ctx, temp));
        resolvedFiles.insert(std::move(temp));
    }
    cmdLine_->files = std::move(resolvedFiles);

    return Result::Success;
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
    addArg("all", "--directory", "-d", CommandLineType::PathSet, &cmdLine_->directories, nullptr,
           "");
    addArg("all", "--file", "-f", CommandLineType::PathSet, &cmdLine_->files, nullptr,
           "");
}

SWC_END_NAMESPACE();
