#include "pch.h"

#include "FileSystem.h"
#include "Global.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Report/Diagnostic.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE()

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
CommandKind CommandLineParser::isAllowedCommand(const Utf8& cmd)
{
    const Utf8         ac = ALLOWED_COMMANDS;
    std::istringstream iss(ac);

    Utf8 allowed;
    int  index = 0;
    while (std::getline(iss, allowed, '|'))
    {
        if (allowed == cmd)
            return static_cast<CommandKind>(index);
        index++;
    }

    return CommandKind::Invalid;
}

void CommandLineParser::setReportArguments(Diagnostic& diag, const Utf8& arg)
{
    diag.addArgument(Diagnostic::ARG_ARG, arg);
    diag.addArgument(Diagnostic::ARG_COMMAND, command_);
    errorRaised_ = true;
}

void CommandLineParser::setReportArguments(Diagnostic& diag, const ArgInfo& info, const Utf8& arg)
{
    setReportArguments(diag, arg);
    diag.addArgument(Diagnostic::ARG_ARG, arg);
    diag.addArgument(Diagnostic::ARG_COMMAND, command_);
    diag.addArgument(Diagnostic::ARG_LONG, info.longForm);
    diag.addArgument(Diagnostic::ARG_SHORT, info.shortForm);
    diag.addArgument(Diagnostic::ARG_VALUES, info.enumValues);
    errorRaised_ = true;
}

bool CommandLineParser::getNextValue(const TaskContext& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value)
{
    if (index + 1 >= argc)
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_arg_val);
        setReportArguments(diag, arg);
        diag.report(ctx);
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

bool CommandLineParser::parseEnumString(const TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, Utf8* target)
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

bool CommandLineParser::parseEnumInt(const TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* target)
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

bool CommandLineParser::reportEnumError(const TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value)
{
    auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_enum);
    setReportArguments(diag, info, arg);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
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

std::optional<ArgInfo> CommandLineParser::findArgument(const TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(ctx, arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
        return findShortFormArgument(ctx, arg, invertBoolean);

    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findLongFormArgument(const TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, LONG_NO_PREFIX_LEN) == LONG_NO_PREFIX && arg.length() > LONG_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, LONG_PREFIX, LONG_NO_PREFIX_LEN, longFormMap_, invertBoolean);
    const auto it = longFormMap_.find(arg);
    if (it != longFormMap_.end())
        return it->second;
    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findShortFormArgument(const TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, SHORT_NO_PREFIX_LEN) == SHORT_NO_PREFIX && arg.length() > SHORT_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, SHORT_PREFIX, SHORT_NO_PREFIX_LEN, shortFormMap_, invertBoolean);
    const auto it = shortFormMap_.find(arg);
    if (it != shortFormMap_.end())
        return it->second;
    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findNegatedArgument(const TaskContext& ctx, const Utf8& arg, const char* prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean)
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
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_bool);
        setReportArguments(diag, info, arg);
        diag.report(ctx);
        return std::nullopt;
    }

    invertBoolean = true;
    return info;
}

void CommandLineParser::reportInvalidArgument(const TaskContext& ctx, const Utf8& arg)
{
    auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_arg);
    setReportArguments(diag, arg);
    diag.report(ctx);
}

bool CommandLineParser::processArgument(const TaskContext& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[])
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

void CommandLineParser::printHelp(const TaskContext& ctx)
{
    ctx.global().logger().lock();
    Logger::printDim(ctx, std::format("swag compiler version {}.{}.{}\n", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
    Logger::printDim(ctx, "Usage:\n");
    Logger::printDim(ctx, "    swag <command> [options]\n");
    ctx.global().logger().unlock();
}

Result CommandLineParser::parse(int argc, char* argv[])
{
    const CompilerContext context(*global_, *cmdLine_);
    const TaskContext     ctx(context);

    if (argc == 1)
    {
        printHelp(ctx);
        return Result::Error;
    }

    // Require a command as the first positional token (no leading '-').
    if (argc <= 1 || argv[1][0] == '-')
    {
        // Missing command name
        const auto diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_command);
        diag.report(ctx);
        return Result::Error;
    }

    // Validate and set the command
    {
        const Utf8 candidate = argv[1];
        cmdLine_->command    = isAllowedCommand(candidate);
        if (cmdLine_->command == CommandKind::Invalid)
        {
            auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_command);
            setReportArguments(diag, argv[1]);
            diag.addArgument(Diagnostic::ARG_VALUES, ALLOWED_COMMANDS);
            diag.report(ctx);
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
            auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_cmd_arg);
            setReportArguments(diag, info.value(), arg);
            diag.report(ctx);
            return Result::Error;
        }

        if (!processArgument(ctx, info.value(), arg, invertBoolean, i, argc, argv))
            return Result::Error;
    }

    return checkCommandLine(ctx);
}

Result CommandLineParser::checkCommandLine(const TaskContext& ctx) const
{
    if (!cmdLine_->verboseDiagFilter.empty())
        cmdLine_->verboseDiag = true;

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

#if SWC_DEV_MODE
    cmdLine_->dbgDevMode = true;
#endif

    return Result::Success;
}

CommandLineParser::CommandLineParser(CommandLine& cmdLine, Global& global) :
    cmdLine_(&cmdLine),
    global_(&global)
{
    addArg("all", "--silent", nullptr, CommandLineType::Bool, &cmdLine_->silent, nullptr, "Suppress all log output.");
    addArg("all", "--stats", nullptr, CommandLineType::Bool, &cmdLine_->stats, nullptr, "Display runtime statistics after execution.");
    addArg("all", "--num-cores", nullptr, CommandLineType::Int, &cmdLine_->numCores, nullptr, "Set the maximum number of CPU cores to use (0 = auto-detect).");
    addArg("all", "--log-color", nullptr, CommandLineType::Bool, &cmdLine_->logColor, nullptr, "Enable colored log output for better readability.");
    addArg("all", "--log-ascii", nullptr, CommandLineType::Bool, &cmdLine_->logAscii, nullptr, "Restrict console output to ASCII characters (disable Unicode).");
    addArg("all", "--syntax-color", "-sc", CommandLineType::Bool, &cmdLine_->syntaxColor, nullptr, "Syntax color output code.");
    addArg("all", "--syntax-color-lum", nullptr, CommandLineType::Int, &cmdLine_->syntaxColorLum, nullptr, "Syntax color luminosity factor [0-100].");
    addArg("all", "--diag-absolute", "-da", CommandLineType::Bool, &cmdLine_->diagAbsolute, nullptr, "Show absolute file paths in diagnostic messages.");
    addArg("all", "--diag-one-line", "-dl", CommandLineType::Bool, &cmdLine_->diagOneLine, nullptr, "Display diagnostics as a single line.");
    addArg("all", "--diag-id", "-did", CommandLineType::Bool, &cmdLine_->errorId, nullptr, "Show diagnostic identifiers.");
    addArg("all", "--verify", "-v", CommandLineType::Bool, &cmdLine_->verify, nullptr, "Verify special test annotations or comments.");
    addArg("all", "--verbose-unittest", "-ve", CommandLineType::Bool, &cmdLine_->verboseDiag, nullptr, "Log raised diagnostics during tests.");
    addArg("all", "--verbose-unittest-filter", "-vef", CommandLineType::String, &cmdLine_->verboseDiagFilter, nullptr, "Filter verbose diagnostics logs by matching a specific string.");
    addArg("all", "--directory", "-d", CommandLineType::PathSet, &cmdLine_->directories, nullptr, "Specify one or more directories to process recursively for input files.");
    addArg("all", "--file", "-f", CommandLineType::PathSet, &cmdLine_->files, nullptr, "Specify one or more individual files to process directly.");
    addArg("all", "--file-filter", "-ff", CommandLineType::StringSet, &cmdLine_->fileFilter, nullptr, "Apply a substring filter to select specific files by name.");
    addArg("all", "--devmode", nullptr, CommandLineType::Bool, &cmdLine_->dbgDevMode, nullptr, "Open a message box in case of hardware exceptions.");

#if SWC_DEV_MODE
    addArg("all", "--randomize", nullptr, CommandLineType::Bool, &cmdLine_->randomize, nullptr, "Randomize behavior.");
    addArg("all", "--seed", nullptr, CommandLineType::Int, &cmdLine_->randSeed, nullptr, "Set seed for randomize behavior.");
#endif
}

SWC_END_NAMESPACE()
