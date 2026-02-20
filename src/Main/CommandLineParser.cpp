#include "pch.h"
#include "Main/CommandLineParser.h"
#include "Main/CommandLine.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

constexpr std::string_view LONG_PREFIX         = "--";
constexpr std::string_view SHORT_PREFIX        = "-";
constexpr std::string_view LONG_NO_PREFIX      = "--no-";
constexpr std::string_view SHORT_NO_PREFIX     = "-no-";
constexpr size_t           LONG_PREFIX_LEN     = 2;
constexpr size_t           SHORT_PREFIX_LEN    = 1;
constexpr size_t           LONG_NO_PREFIX_LEN  = 5;
constexpr size_t           SHORT_NO_PREFIX_LEN = 4;

// Pipe-delimited list of allowed command names.
// Adjust to match your tool's commands.
CommandKind CommandLineParser::isAllowedCommand(const Utf8& cmd)
{
    int index = 0;
    for (const CommandInfo& allowed : COMMANDS)
    {
        if (allowed.name == cmd)
            return static_cast<CommandKind>(index);
        index++;
    }

    return CommandKind::Invalid;
}

Utf8 CommandLineParser::getAllowedCommands()
{
    Utf8 result;
    for (const CommandInfo& cmd : COMMANDS)
    {
        if (!result.empty())
            result += "|";
        result += cmd.name;
    }
    return result;
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

bool CommandLineParser::getNextValue(TaskContext& ctx, const Utf8& arg, int& index, int argc, char* argv[], Utf8& value)
{
    if (index + 1 >= argc)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_arg_val);
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

bool CommandLineParser::parseEnumString(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, Utf8* target)
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

bool CommandLineParser::parseEnumInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* target)
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

bool CommandLineParser::reportEnumError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_enum);
    setReportArguments(diag, info, arg);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.report(ctx);
    return false;
}

void CommandLineParser::addArg(HelpOptionGroup group, const char* commands, const char* longForm, const char* shortForm, CommandLineType type, void* target, const char* enumValues, const char* description)
{
    ArgInfo info;
    info.commands    = commands ? commands : "";
    info.longForm    = longForm ? longForm : "";
    info.shortForm   = shortForm ? shortForm : "";
    info.type        = type;
    info.target      = target;
    info.enumValues  = enumValues ? enumValues : "";
    info.group       = group;
    info.description = description ? description : "";

    args_.push_back(info);

    if (!info.longForm.empty())
        longFormMap_[info.longForm] = args_.back();
    if (!info.shortForm.empty())
        shortFormMap_[info.shortForm] = args_.back();
}

std::optional<ArgInfo> CommandLineParser::findArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(ctx, arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
        return findShortFormArgument(ctx, arg, invertBoolean);

    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findLongFormArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, LONG_NO_PREFIX_LEN) == LONG_NO_PREFIX && arg.length() > LONG_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, LONG_PREFIX, LONG_NO_PREFIX_LEN, longFormMap_, invertBoolean);
    const auto it = longFormMap_.find(arg);
    if (it != longFormMap_.end())
        return it->second;
    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findShortFormArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    if (arg.substr(0, SHORT_NO_PREFIX_LEN) == SHORT_NO_PREFIX && arg.length() > SHORT_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, SHORT_PREFIX, SHORT_NO_PREFIX_LEN, shortFormMap_, invertBoolean);
    const auto it = shortFormMap_.find(arg);
    if (it != shortFormMap_.end())
        return it->second;
    return std::nullopt;
}

std::optional<ArgInfo> CommandLineParser::findNegatedArgument(TaskContext& ctx, const Utf8& arg, std::string_view prefix, size_t noPrefixLen, const std::map<Utf8, ArgInfo>& argMap, bool& invertBoolean)
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
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_bool);
        setReportArguments(diag, info, arg);
        diag.report(ctx);
        return std::nullopt;
    }

    invertBoolean = true;
    return info;
}

void CommandLineParser::reportInvalidArgument(TaskContext& ctx, const Utf8& arg)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_arg);
    setReportArguments(diag, arg);
    diag.report(ctx);
}

bool CommandLineParser::processArgument(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, int& index, int argc, char* argv[])
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

        case CommandLineType::UnsignedInt:
            if (!getNextValue(ctx, arg, index, argc, argv, value))
                return false;
            *static_cast<uint32_t*>(info.target) = std::stoul(value);
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

Result CommandLineParser::parse(int argc, char* argv[])
{
    TaskContext ctx(*global_, *cmdLine_);

    if (argc == 1 || (argc == 2 && (Utf8(argv[1]) == "--help" || Utf8(argv[1]) == "help")))
    {
        CommandLineParser parser(*global_, *cmdLine_);
        parser.printHelp(ctx);
        return Result::Error;
    }

    if (argc >= 2 && Utf8(argv[1]) == "help")
    {
        const Utf8        command = argc >= 3 ? argv[2] : "";
        CommandLineParser parser(*global_, *cmdLine_);
        if (!command.empty() && isAllowedCommand(command) == CommandKind::Invalid)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_command);
            parser.setReportArguments(diag, command);
            diag.addArgument(Diagnostic::ARG_VALUES, getAllowedCommands());
            diag.report(ctx);
            return Result::Error;
        }

        parser.printHelp(ctx, command);
        return Result::Error;
    }

    // Require a command as the first positional token (no leading '-').
    if (argc <= 1 || argv[1][0] == '-')
    {
        // Missing command name
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_command);
        diag.report(ctx);
        return Result::Error;
    }

    // Validate and set the command
    {
        const Utf8 candidate = argv[1];
        cmdLine_->command    = isAllowedCommand(candidate);
        if (cmdLine_->command == CommandKind::Invalid)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_command);
            setReportArguments(diag, argv[1]);
            diag.addArgument(Diagnostic::ARG_VALUES, getAllowedCommands());
            diag.report(ctx);
            return Result::Error;
        }

        command_ = candidate;
    }

    for (int i = 2; i < argc; i++)
    {
        Utf8 arg           = argv[i];
        bool invertBoolean = false;

        const std::optional<ArgInfo> info = findArgument(ctx, arg, invertBoolean);
        if (!info)
        {
            if (!errorRaised_)
                reportInvalidArgument(ctx, arg);
            return Result::Error;
        }

        if (!commandMatches(info.value().commands))
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_cmd_arg);
            setReportArguments(diag, info.value(), arg);
            diag.report(ctx);
            return Result::Error;
        }

        if (!processArgument(ctx, info.value(), arg, invertBoolean, i, argc, argv))
            return Result::Error;
    }

    return checkCommandLine(ctx);
}

Result CommandLineParser::checkCommandLine(TaskContext& ctx) const
{
    if (!cmdLine_->verboseVerifyFilter.empty())
        cmdLine_->verboseVerify = true;

    if (cmdLine_->targetArchName == "x86_64")
        cmdLine_->targetArch = Runtime::TargetArch::X86_64;
    else
        SWC_UNREACHABLE();

#if SWC_DEV_MODE
    if (cmdLine_->randSeed)
        cmdLine_->randomize = true;

    if (cmdLine_->randomize)
        cmdLine_->numCores = 1;
#endif

    // Resolve all folders
    std::set<fs::path> resolvedFolders;
    for (const fs::path& folder : cmdLine_->directories)
    {
        fs::path temp = folder;
        RESULT_VERIFY(FileSystem::resolveFolder(ctx, temp));
        resolvedFolders.insert(std::move(temp));
    }
    cmdLine_->directories = std::move(resolvedFolders);

    // Resolve all files
    std::set<fs::path> resolvedFiles;
    for (const fs::path& file : cmdLine_->files)
    {
        fs::path temp = file;
        RESULT_VERIFY(FileSystem::resolveFile(ctx, temp));
        resolvedFiles.insert(std::move(temp));
    }
    cmdLine_->files = std::move(resolvedFiles);

    // Module path should exist
    if (!cmdLine_->modulePath.empty())
    {
        fs::path temp = cmdLine_->modulePath;
        RESULT_VERIFY(FileSystem::resolveFolder(ctx, temp));
        cmdLine_->modulePath = std::move(temp);
    }

    return Result::Continue;
}

CommandLineParser::CommandLineParser(Global& global, CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global)
{
    addArg(HelpOptionGroup::Input, "all", "--directory", "-d", CommandLineType::PathSet, &cmdLine_->directories, nullptr, "Specify one or more directories to process recursively for input files.");
    addArg(HelpOptionGroup::Input, "all", "--file", "-f", CommandLineType::PathSet, &cmdLine_->files, nullptr, "Specify one or more individual files to process directly.");
    addArg(HelpOptionGroup::Input, "all", "--file-filter", "-ff", CommandLineType::StringSet, &cmdLine_->fileFilter, nullptr, "Apply a substring filter to select specific files by name.");
    addArg(HelpOptionGroup::Input, "all", "--module", "-m", CommandLineType::Path, &cmdLine_->modulePath, nullptr, "Specify a module path to compile.");
    addArg(HelpOptionGroup::Input, "all", "--runtime", nullptr, CommandLineType::Bool, &cmdLine_->runtime, nullptr, "Add runtime files.");

    addArg(HelpOptionGroup::Target, "all", "--arch", nullptr, CommandLineType::EnumString, &cmdLine_->targetArchName, "x86_64", "Set the target architecture used by #arch.");
    addArg(HelpOptionGroup::Target, "all", "--cfg", nullptr, CommandLineType::String, &cmdLine_->buildCfg, nullptr, "Set the build configuration string used by #cfg.");
    addArg(HelpOptionGroup::Target, "all", "--cpu", nullptr, CommandLineType::String, &cmdLine_->targetCpu, nullptr, "Set the target CPU string used by #cpu.");
    addArg(HelpOptionGroup::Target, "all", "--debug-info", nullptr, CommandLineType::Bool, &cmdLine_->debugInfo, nullptr, "Enable backend micro-instruction debug information.");
    addArg(HelpOptionGroup::Target, "all", "--backend-optimize", nullptr, CommandLineType::EnumString, &cmdLine_->backendOptimizeLevelOverride, "O0|O1|O2|O3|Os|Oz", "Override default backend optimization level.");

    addArg(HelpOptionGroup::Compiler, "all", "--num-cores", nullptr, CommandLineType::UnsignedInt, &cmdLine_->numCores, nullptr, "Set the maximum number of CPU cores to use (0 = auto-detect).");
    addArg(HelpOptionGroup::Compiler, "all", "--stats", nullptr, CommandLineType::Bool, &cmdLine_->stats, nullptr, "Display runtime statistics after execution.");

    addArg(HelpOptionGroup::Diagnostics, "all", "--file-path-display", "-fpd", CommandLineType::EnumInt, &cmdLine_->filePathDisplay, "as-is|basename|absolute", "Control file path display style for diagnostics, stack traces and file locations.");
    addArg(HelpOptionGroup::Diagnostics, "all", "--diag-id", "-did", CommandLineType::Bool, &cmdLine_->errorId, nullptr, "Show diagnostic identifiers.");
    addArg(HelpOptionGroup::Diagnostics, "all", "--diag-one-line", "-dl", CommandLineType::Bool, &cmdLine_->diagOneLine, nullptr, "Display diagnostics as a single line.");
    addArg(HelpOptionGroup::Diagnostics, "all", "--verbose-verify", "-vv", CommandLineType::Bool, &cmdLine_->verboseVerify, nullptr, "Log diagnostics that are normally suppressed by --verify.");
    addArg(HelpOptionGroup::Diagnostics, "all", "--verbose-verify-filter", "-vvf", CommandLineType::String, &cmdLine_->verboseVerifyFilter, nullptr, "Filter --verbose-verify logs by matching a specific string.");
    addArg(HelpOptionGroup::Diagnostics, "all", "--verify", "-v", CommandLineType::Bool, &cmdLine_->verify, nullptr, "Verify source-file expected diagnostics comments.");

    addArg(HelpOptionGroup::LoggingAndOutput, "all", "--log-ascii", nullptr, CommandLineType::Bool, &cmdLine_->logAscii, nullptr, "Restrict console output to ASCII characters (disable Unicode).");
    addArg(HelpOptionGroup::LoggingAndOutput, "all", "--log-color", nullptr, CommandLineType::Bool, &cmdLine_->logColor, nullptr, "Enable colored log output for better readability.");
    addArg(HelpOptionGroup::LoggingAndOutput, "all", "--silent", nullptr, CommandLineType::Bool, &cmdLine_->silent, nullptr, "Suppress all log output.");
    addArg(HelpOptionGroup::LoggingAndOutput, "all", "--syntax-color", "-sc", CommandLineType::Bool, &cmdLine_->syntaxColor, nullptr, "Syntax color output code.");
    addArg(HelpOptionGroup::LoggingAndOutput, "all", "--syntax-color-lum", nullptr, CommandLineType::UnsignedInt, &cmdLine_->syntaxColorLum, nullptr, "Syntax color luminosity factor [0-100].");

    addArg(HelpOptionGroup::Testing, "all", "--unittest", "-ut", CommandLineType::Bool, &cmdLine_->internalUnittest, nullptr, "Run internal C++ unit tests before executing command.");
    addArg(HelpOptionGroup::Testing, "all", "--verbose-unittest", "-vut", CommandLineType::Bool, &cmdLine_->verboseInternalUnittest, nullptr, "Print each internal unit test status.");

    addArg(HelpOptionGroup::Development, "all", "--devmode", nullptr, CommandLineType::Bool, &CommandLine::dbgDevMode, nullptr, "Open a message box in case of errors.");
#if SWC_DEV_MODE
    addArg(HelpOptionGroup::Development, "all", "--randomize", nullptr, CommandLineType::Bool, &cmdLine_->randomize, nullptr, "Randomize behavior. Forces --num-cores=1.");
    addArg(HelpOptionGroup::Development, "all", "--seed", nullptr, CommandLineType::UnsignedInt, &cmdLine_->randSeed, nullptr, "Set seed for randomize behavior. Forces --randomize and --num-cores=1.");
#endif
}

SWC_END_NAMESPACE();
