#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

constexpr std::string_view LONG_PREFIX        = "--";
constexpr std::string_view SHORT_PREFIX       = "-";
constexpr std::string_view LONG_NO_PREFIX     = "--no-";
constexpr size_t           LONG_PREFIX_LEN    = 2;
constexpr size_t           SHORT_PREFIX_LEN   = 1;
constexpr size_t           LONG_NO_PREFIX_LEN = 5;
constexpr std::string_view END_OF_OPTIONS     = "--";

namespace
{
    constexpr uint32_t         RSP_MAX_DEPTH          = 16;
    constexpr std::string_view CONFIG_FILE_LONG_FORM  = "--config-file";
    constexpr std::string_view CONFIG_FILE_SHORT_FORM = "-cf";

    void resolveModuleRelativeInput(const fs::path& baseDir, fs::path& path)
    {
        if (baseDir.empty() || !path.is_relative())
            return;

        path = (baseDir / path).lexically_normal();
    }

    // Split response-file content into whitespace-separated tokens.
    // Supports `"..."` and `'...'` for tokens containing spaces. No escape sequences.
    // Returns false if a quote is left unterminated.
    bool tokenizeResponseFile(std::string_view content, std::vector<Utf8>& out)
    {
        Utf8 token;
        char quote = 0;
        bool inTok = false;

        for (const char c : content)
        {
            if (quote)
            {
                if (c == quote)
                    quote = 0;
                else
                    token.push_back(c);
                continue;
            }

            if (c == '"' || c == '\'')
            {
                quote = c;
                inTok = true;
                continue;
            }

            if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v')
            {
                if (inTok)
                {
                    out.push_back(token);
                    token.clear();
                    inTok = false;
                }
                continue;
            }

            token.push_back(c);
            inTok = true;
        }

        if (quote)
            return false;

        if (inTok)
        {
            out.push_back(token);
            token.clear();
        }

        return true;
    }

    bool hasRegisteredBuildCfg(const Runtime::BuildCfg& buildCfg, const std::string_view cfgName)
    {
        if (cfgName.empty())
            return false;

        if (!buildCfg.registeredConfigs.ptr || !buildCfg.registeredConfigs.length)
            return false;

        const std::string_view registered = {buildCfg.registeredConfigs.ptr, buildCfg.registeredConfigs.length};
        size_t                 start      = 0;
        while (start <= registered.size())
        {
            size_t end = registered.find('|', start);
            if (end == std::string_view::npos)
                end = registered.size();

            if (registered.substr(start, end - start) == cfgName)
                return true;

            if (end == registered.size())
                break;

            start = end + 1;
        }

        return false;
    }

    bool isSwagScriptPath(const fs::path& path)
    {
        std::string ext = path.extension().string();
        std::ranges::transform(ext, ext.begin(), [](const char c) { return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c; });
        return ext == ".swgs";
    }

    void configureScriptCommand(CommandLine& cmdLine, const fs::path& scriptPath)
    {
        cmdLine.command         = CommandKind::Run;
        cmdLine.commandExplicit = true;
        cmdLine.scriptMode      = true;
        cmdLine.moduleFilePath  = scriptPath;
        cmdLine.files.insert(scriptPath);
    }

    void splitInlineOptionValue(const Utf8& raw, Utf8& lookup, std::optional<Utf8>& inlineValue)
    {
        lookup = raw;
        inlineValue.reset();
        if (raw.substr(0, SHORT_PREFIX_LEN) != SHORT_PREFIX)
            return;

        const size_t eq = raw.find('=');
        if (eq == Utf8::npos)
            return;

        lookup      = raw.substr(0, eq);
        inlineValue = raw.substr(eq + 1);
    }

    template<typename T>
    bool parseIntegerValue(std::string_view value, T& result)
    {
        const char* first       = value.data();
        const char* last        = first + value.size();
        const auto [ptr, error] = std::from_chars(first, last, result);
        return !value.empty() && error == std::errc{} && ptr == last;
    }

    Result reportConflictingArgument(TaskContext& ctx, const std::string_view arg, const std::string_view otherArg)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_conflicting_arg);
        diag.addArgument(Diagnostic::ARG_ARG, arg);
        diag.addArgument(Diagnostic::ARG_VALUE, otherArg);
        diag.report(ctx);
        return Result::Error;
    }

    template<typename T>
    Result resolveInputPathSet(TaskContext& ctx, const fs::path& baseDir, std::set<fs::path>& paths, T resolvePath)
    {
        std::set<fs::path> resolvedPaths;
        for (const fs::path& rawPath : paths)
        {
            fs::path temp = rawPath;
            resolveModuleRelativeInput(baseDir, temp);
            SWC_RESULT(resolvePath(ctx, temp));
            resolvedPaths.insert(std::move(temp));
        }

        paths = std::move(resolvedPaths);
        return Result::Continue;
    }

    Result normalizeAbsoluteDirectory(TaskContext& ctx, fs::path& path, Utf8* storage = nullptr)
    {
        if (path.empty())
        {
            if (storage)
                storage->clear();
            return Result::Continue;
        }

        fs::path temp = path;
        Utf8     because;
        if (FileSystem::normalizeAbsolutePath(temp, because) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, temp, because);
            diag.report(ctx);
            return Result::Error;
        }

        path = std::move(temp);
        if (storage)
            *storage = Utf8(path);
        return Result::Continue;
    }

    bool applyBuildCfgPreset(Runtime::BuildCfg& buildCfg, const std::string_view cfgName)
    {
        if (cfgName == "fast-compile")
        {
            buildCfg.safetyGuards              = Runtime::SafetyWhat::None;
            buildCfg.sanity                    = false;
            buildCfg.allocatorCaptureStack     = false;
            buildCfg.allocatorLeaks            = false;
            buildCfg.allocatorTrackAllocations = false;
            buildCfg.allocatorElectricMode     = false;
            buildCfg.allocatorFillMemory       = false;
            buildCfg.errorStackTrace           = false;
            buildCfg.backend.optimize          = false;
            buildCfg.backend.debugInfo         = false;
            buildCfg.backend.inlineMode        = Runtime::BuildCfgBackendInlineMode::Never;
        }
        else if (cfgName == "debug")
        {
            buildCfg.safetyGuards              = Runtime::SafetyWhat::All;
            buildCfg.sanity                    = true;
            buildCfg.allocatorCaptureStack     = true;
            buildCfg.allocatorLeaks            = true;
            buildCfg.allocatorTrackAllocations = true;
            buildCfg.allocatorElectricMode     = false;
            buildCfg.allocatorFillMemory       = true;
            buildCfg.errorStackTrace           = true;
            buildCfg.backend.optimize          = false;
            buildCfg.backend.debugInfo         = true;
            buildCfg.backend.inlineMode        = Runtime::BuildCfgBackendInlineMode::Never;
        }
        else if (cfgName == "fast-debug")
        {
            buildCfg.safetyGuards              = Runtime::SafetyWhat::All;
            buildCfg.sanity                    = true;
            buildCfg.allocatorCaptureStack     = false;
            buildCfg.allocatorLeaks            = true;
            buildCfg.allocatorTrackAllocations = false;
            buildCfg.allocatorElectricMode     = false;
            buildCfg.allocatorFillMemory       = false;
            buildCfg.errorStackTrace           = true;
            buildCfg.backend.optimize          = true;
            buildCfg.backend.debugInfo         = true;
            buildCfg.backend.inlineMode        = Runtime::BuildCfgBackendInlineMode::MarkedOnly;
        }
        else if (cfgName == "release")
        {
            buildCfg.safetyGuards               = Runtime::SafetyWhat::None;
            buildCfg.sanity                     = false;
            buildCfg.allocatorCaptureStack      = false;
            buildCfg.allocatorLeaks             = false;
            buildCfg.allocatorTrackAllocations  = false;
            buildCfg.allocatorElectricMode      = false;
            buildCfg.allocatorFillMemory        = false;
            buildCfg.errorStackTrace            = false;
            buildCfg.backend.optimize           = true;
            buildCfg.backend.debugInfo          = true;
            buildCfg.backend.fpMathFma          = true;
            buildCfg.backend.fpMathNoNaN        = true;
            buildCfg.backend.fpMathNoInf        = true;
            buildCfg.backend.fpMathNoSignedZero = true;
            buildCfg.backend.inlineMode         = Runtime::BuildCfgBackendInlineMode::Auto;
        }
        else
        {
            return false;
        }

        return true;
    }

    void updateDefaultBuildCfg(CommandLine& cmdLine)
    {
        cmdLine.sourceDrivenTest = cmdLine.command == CommandKind::Test;

        Runtime::BuildCfg buildCfg{};
        if (cmdLine.defaultBuildCfg.registeredConfigs.ptr && cmdLine.defaultBuildCfg.registeredConfigs.length)
            buildCfg.registeredConfigs = cmdLine.defaultBuildCfg.registeredConfigs;

        SWC_ASSERT(hasRegisteredBuildCfg(buildCfg, cmdLine.buildCfg.view()));
        SWC_INTERNAL_CHECK(applyBuildCfgPreset(buildCfg, cmdLine.buildCfg.view()));

        if (cmdLine.backendOptimize.has_value())
            buildCfg.backend.optimize = cmdLine.backendOptimize.value();

        buildCfg.backendKind = cmdLine.backendKind;

        if (cmdLine.sourceDrivenTest)
        {
            buildCfg.backend.debugInfo        = true;
            buildCfg.backend.enableExceptions = true;
        }

        cmdLine.moduleNamespaceStorage = cmdLine.moduleNamespace;
        if (cmdLine.moduleNamespaceStorage.empty())
            cmdLine.moduleNamespaceStorage = defaultModuleNamespace(defaultArtifactName(cmdLine));

        buildCfg.moduleNamespace = Utf8Helper::runtimeStringFromUtf8(cmdLine.moduleNamespaceStorage);
        buildCfg.name            = Utf8Helper::runtimeStringFromUtf8(cmdLine.name);
        buildCfg.outDir          = Utf8Helper::runtimeStringFromUtf8(cmdLine.outDirStorage);
        buildCfg.workDir         = Utf8Helper::runtimeStringFromUtf8(cmdLine.workDirStorage);
        cmdLine.defaultBuildCfg  = buildCfg;
    }

    fs::path commandInputBaseDir(const CommandLine& cmdLine)
    {
        if (!cmdLine.workspacePath.empty())
            return cmdLine.workspacePath;

        if (cmdLine.moduleFilePath.empty())
            return {};

        return cmdLine.moduleFilePath.parent_path();
    }

    void markExplicitBuildCfgOverride(CommandLine& cmdLine, const ArgTarget& target)
    {
        if (const auto* t = std::get_if<Utf8*>(&target))
        {
            if (*t == &cmdLine.buildCfg)
                cmdLine.buildCfgExplicit = true;
            else if (*t == &cmdLine.name)
                cmdLine.artifactNameExplicit = true;
            else if (*t == &cmdLine.moduleNamespace)
                cmdLine.moduleNamespaceExplicit = true;
            return;
        }

        if (const auto* t = std::get_if<fs::path*>(&target))
        {
            if (*t == &cmdLine.outDir)
                cmdLine.outDirExplicit = true;
            else if (*t == &cmdLine.workDir)
                cmdLine.workDirExplicit = true;
            return;
        }

        if (const auto* t = std::get_if<EnumIntTarget>(&target); t && t->target == &cmdLine.backendKind)
            cmdLine.artifactKindExplicit = true;
    }
}

void CommandLineParser::refreshBuildCfg(CommandLine& cmdLine)
{
    if (cmdLine.command == CommandKind::Test)
        cmdLine.sourceDrivenTest = true;
    updateDefaultBuildCfg(cmdLine);
}

CommandKind CommandLineParser::isAllowedCommand(const Utf8& cmd)
{
    for (const CommandInfo& allowed : COMMANDS)
    {
        if (allowed.name == cmd)
            return allowed.kind;
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
    diag.addArgument(Diagnostic::ARG_LONG, info.longForm);
    diag.addArgument(Diagnostic::ARG_SHORT, info.shortForm);

    Utf8 values;
    for (const Utf8& c : info.choices)
    {
        if (!values.empty())
            values += "|";
        values += c;
    }
    diag.addArgument(Diagnostic::ARG_VALUES, values);
    errorRaised_ = true;
}

Result CommandLineParser::expandResponseFiles(TaskContext& ctx, const std::vector<Utf8>& in, std::vector<Utf8>& out)
{
    std::set<fs::path> visited;
    out.reserve(in.size());

    for (const Utf8& token : in)
    {
        if (!token.empty() && token[0] == '@' && token.size() > 1)
        {
            const fs::path path = token.substr(1).c_str();
            SWC_RESULT(expandOneResponseFile(ctx, path, out, visited, 0));
            continue;
        }

        out.push_back(token);
    }

    return Result::Continue;
}

Result CommandLineParser::expandOneResponseFile(TaskContext& ctx, const fs::path& path, std::vector<Utf8>& out, std::set<fs::path>& visited, uint32_t depth)
{
    const fs::path normalizedPath = FileSystem::normalizePath(path);
    if (depth >= RSP_MAX_DEPTH)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_depth);
        FileSystem::setDiagnosticPath(diag, &ctx, normalizedPath);
        diag.report(ctx);
        return Result::Error;
    }

    const fs::path& canonical = normalizedPath;

    if (!visited.insert(canonical).second)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_cycle);
        FileSystem::setDiagnosticPath(diag, &ctx, canonical);
        diag.report(ctx);
        return Result::Error;
    }

    std::string             content;
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::readTextFile(canonical, content, ioError) != Result::Continue)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, canonical, FileSystem::describeIoFailure(ioError));
        diag.report(ctx);
        return Result::Error;
    }

    std::vector<Utf8> tokens;
    if (!tokenizeResponseFile(content, tokens))
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_unterminated);
        FileSystem::setDiagnosticPath(diag, &ctx, canonical);
        diag.report(ctx);
        return Result::Error;
    }

    for (const Utf8& token : tokens)
    {
        if (!token.empty() && token[0] == '@' && token.size() > 1)
        {
            const fs::path nestedRaw = token.substr(1).c_str();
            fs::path       nested    = nestedRaw;
            if (nested.is_relative())
                nested = canonical.parent_path() / nested;
            SWC_RESULT(expandOneResponseFile(ctx, nested, out, visited, depth + 1));
            continue;
        }

        out.push_back(token);
    }

    visited.erase(canonical);
    return Result::Continue;
}

bool CommandLineParser::getNextValue(TaskContext& ctx, const Utf8& arg, const Utf8* inlineValue, size_t& index, const std::vector<Utf8>& args, Utf8& value)
{
    if (inlineValue)
    {
        value = *inlineValue;
        return true;
    }

    if (index + 1 >= args.size())
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_arg_val);
        setReportArguments(diag, arg);
        diag.report(ctx);
        return false;
    }

    value = args[++index];
    return true;
}

Result CommandLineParser::applyConfigFile(TaskContext& ctx, const std::vector<Utf8>& args)
{
    fs::path configPath;

    for (size_t i = 0; i < args.size(); i++)
    {
        const Utf8& raw = args[i];

        Utf8                lookup = raw;
        std::optional<Utf8> inlineValue;
        splitInlineOptionValue(raw, lookup, inlineValue);

        if (lookup != CONFIG_FILE_LONG_FORM && lookup != CONFIG_FILE_SHORT_FORM)
            continue;

        Utf8        value;
        const Utf8* inlinePtr = inlineValue.has_value() ? &inlineValue.value() : nullptr;
        if (!getNextValue(ctx, raw, inlinePtr, i, args, value))
            return Result::Error;

        fs::path path = value.c_str();
        Utf8     because;
        if (FileSystem::resolveExistingFile(path, because) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
            diag.report(ctx);
            return Result::Error;
        }

        configPath = std::move(path);
    }

    if (configPath.empty())
        return Result::Continue;

    cmdLine_->configFile = configPath;

    const StructConfigReader reader(configSchema_);
    return reader.readFile(ctx, configPath);
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
    if (info.choices.empty())
    {
        *target = value;
        return true;
    }

    for (const Utf8& allowed : info.choices)
    {
        if (allowed == value)
        {
            *target = value;
            return true;
        }
    }

    return reportEnumError(ctx, info, arg, value);
}

bool CommandLineParser::parseEnumInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, const EnumIntTarget& target)
{
    for (size_t i = 0; i < info.choices.size(); i++)
    {
        if (info.choices[i] == value)
        {
            target.setter(target.target, info.choiceIntValues[i]);
            return true;
        }
    }

    return reportEnumError(ctx, info, arg, value);
}

bool CommandLineParser::reportEnumError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_enum);
    setReportArguments(diag, info, arg);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.addDidYouMeanNote(Utf8Helper::bestMatch(value, info.choices));
    diag.report(ctx);
    return false;
}

bool CommandLineParser::reportIntError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_int);
    setReportArguments(diag, info, arg);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.report(ctx);
    return false;
}

void CommandLineParser::registerConfigEntry(const ArgInfo& info, const StructConfigAssignHook hook)
{
    if (info.longForm.empty())
        return;

    SWC_ASSERT(info.longForm.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX);

    StructConfigEntry& entry = configSchema_.add(info.longForm.substr(LONG_PREFIX_LEN).c_str(), info.target, info.description.c_str(), hook);
    entry.target             = info.target;
    entry.choices            = info.choices;
    entry.choiceIntValues    = info.choiceIntValues;
}

ArgInfo& CommandLineParser::addImpl(HelpOptionGroup group, const char* commands, const char* longForm, const char* shortForm, const char* description, const ArgTarget& target)
{
    ArgInfo info;
    info.commands    = commands ? commands : "";
    info.longForm    = longForm ? longForm : "";
    info.shortForm   = shortForm ? shortForm : "";
    info.description = description ? description : "";
    info.group       = group;
    info.target      = target;

    SWC_ASSERT(info.longForm.empty() || !longFormMap_.contains(info.longForm));
    SWC_ASSERT(info.shortForm.empty() || !shortFormMap_.contains(info.shortForm));

    const size_t idx = args_.size();
    if (!info.longForm.empty())
        longFormMap_[info.longForm] = idx;
    if (!info.shortForm.empty())
        shortFormMap_[info.shortForm] = idx;
    args_.push_back(std::move(info));
    return args_.back();
}

void CommandLineParser::addEnum(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, Utf8* target, std::vector<Utf8> choices, const char* desc, const bool allowInConfig, const StructConfigAssignHook hook)
{
    ArgInfo& info = addImpl(g, cmds, lf, sf, desc, target);
    info.choices  = std::move(choices);
    if (allowInConfig)
        registerConfigEntry(info, hook);
}

const ArgInfo* CommandLineParser::findArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(ctx, arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
    {
        SWC_UNUSED(ctx);
        const auto it = shortFormMap_.find(arg);
        if (it != shortFormMap_.end())
            return &args_[it->second];
    }

    return nullptr;
}

const ArgInfo* CommandLineParser::findLongFormArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    const auto it = longFormMap_.find(arg);
    if (it != longFormMap_.end())
        return &args_[it->second];
    if (arg.substr(0, LONG_NO_PREFIX_LEN) == LONG_NO_PREFIX && arg.length() > LONG_NO_PREFIX_LEN)
        return findNegatedArgument(ctx, arg, invertBoolean);
    return nullptr;
}

const ArgInfo* CommandLineParser::findNegatedArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    const Utf8 baseArg = Utf8(LONG_PREFIX) + arg.substr(LONG_NO_PREFIX_LEN);
    const auto it      = longFormMap_.find(baseArg);

    if (it == longFormMap_.end())
    {
        reportInvalidArgument(ctx, arg);
        return nullptr;
    }

    const ArgInfo& info = args_[it->second];
    if (!info.isBoolLike())
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_bool);
        setReportArguments(diag, info, arg);
        diag.report(ctx);
        return nullptr;
    }

    invertBoolean = true;
    return &info;
}

void CommandLineParser::reportInvalidArgument(TaskContext& ctx, const Utf8& arg)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_arg);
    setReportArguments(diag, arg);
    diag.addDidYouMeanNote(suggestArgument(arg));
    diag.report(ctx);
}

std::optional<Utf8> CommandLineParser::suggestArgument(const Utf8& query) const
{
    std::vector<Utf8> candidates;
    candidates.reserve(args_.size() * 2);
    for (const ArgInfo& a : args_)
    {
        if (!a.longForm.empty())
        {
            candidates.push_back(a.longForm);
            if (a.isBoolLike())
                candidates.emplace_back(Utf8(LONG_NO_PREFIX) + a.longForm.substr(LONG_PREFIX_LEN));
        }
        if (!a.shortForm.empty())
            candidates.push_back(a.shortForm);
    }
    return Utf8Helper::bestMatch(query, candidates);
}

std::optional<Utf8> CommandLineParser::suggestCommand(const Utf8& query)
{
    std::vector<Utf8> candidates;
    candidates.reserve(std::size(COMMANDS));
    for (const CommandInfo& cmd : COMMANDS)
        candidates.emplace_back(cmd.name);
    return Utf8Helper::bestMatch(query, candidates);
}

bool CommandLineParser::processArgument(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, const Utf8* inlineValue, size_t& index, const std::vector<Utf8>& args)
{
    // Boolean-like flags never take a value.
    if (info.isBoolLike())
    {
        if (inlineValue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_unexpected_value);
            setReportArguments(diag, info, arg);
            diag.report(ctx);
            return false;
        }

        const bool v = !invertBoolean;
        if (auto* t = std::get_if<bool*>(&info.target))
            **t = v;
        else if (auto* t1 = std::get_if<std::optional<bool>*>(&info.target))
            **t1 = v;
        else
            SWC_UNREACHABLE();
        return true;
    }

    Utf8 value;
    if (!getNextValue(ctx, arg, inlineValue, index, args, value))
        return false;

    if (auto* t = std::get_if<int*>(&info.target))
    {
        int parsedValue = 0;
        if (!parseIntegerValue(value, parsedValue))
            return reportIntError(ctx, info, arg, value);
        **t = parsedValue;
        return true;
    }
    if (auto* t = std::get_if<uint32_t*>(&info.target))
    {
        uint32_t parsedValue = 0;
        if (!parseIntegerValue(value, parsedValue))
            return reportIntError(ctx, info, arg, value);
        **t = parsedValue;
        return true;
    }
    if (auto* t = std::get_if<Utf8*>(&info.target))
    {
        if (info.isEnum())
        {
            const bool parsed = parseEnumString(ctx, info, arg, value, *t);
            if (parsed)
                markExplicitBuildCfgOverride(*cmdLine_, info.target);
            return parsed;
        }
        **t = value;
        markExplicitBuildCfgOverride(*cmdLine_, info.target);
        return true;
    }
    if (auto* t = std::get_if<fs::path*>(&info.target))
    {
        **t = value.c_str();
        markExplicitBuildCfgOverride(*cmdLine_, info.target);
        return true;
    }
    if (auto* t = std::get_if<std::vector<Utf8>*>(&info.target))
    {
        (*t)->push_back(value);
        return true;
    }
    if (auto* t = std::get_if<std::set<Utf8>*>(&info.target))
    {
        (*t)->insert(value);
        return true;
    }
    if (auto* t = std::get_if<std::set<fs::path>*>(&info.target))
    {
        (*t)->insert(value.c_str());
        return true;
    }
    if (auto* t = std::get_if<EnumIntTarget>(&info.target))
    {
        const bool parsed = parseEnumInt(ctx, info, arg, value, *t);
        if (parsed)
            markExplicitBuildCfgOverride(*cmdLine_, info.target);
        return parsed;
    }

    SWC_UNREACHABLE();
}

Result CommandLineParser::parse(int argc, char* argv[])
{
    TaskContext ctx(*global_, *cmdLine_);

    std::vector<Utf8> rawArgs;
    rawArgs.reserve(argc > 1 ? static_cast<size_t>(argc) - 1 : 0);
    for (int i = 1; i < argc; i++)
        rawArgs.emplace_back(argv[i]);

    std::vector<Utf8> args;
    SWC_RESULT(expandResponseFiles(ctx, rawArgs, args));

    if (args.empty() || (args.size() == 1 && (args[0] == "--help" || args[0] == "help")))
    {
        CommandLineParser parser(*global_, *cmdLine_);
        parser.printHelp(ctx);
        return Result::Error;
    }

    if (!args.empty() && args[0] == "help")
    {
        const Utf8        command = args.size() >= 2 ? args[1] : "";
        CommandLineParser parser(*global_, *cmdLine_);
        if (!command.empty() && isAllowedCommand(command) == CommandKind::Invalid)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_command);
            parser.setReportArguments(diag, command);
            diag.addArgument(Diagnostic::ARG_VALUES, getAllowedCommands());
            diag.addDidYouMeanNote(suggestCommand(command));
            diag.report(ctx);
            return Result::Error;
        }

        parser.printHelp(ctx, command);
        return Result::Error;
    }

    SWC_RESULT(applyConfigFile(ctx, args));

    size_t argStartIndex = 0;
    if (!args.empty() && !args[0].empty() && args[0][0] != '-')
    {
        const Utf8& candidate = args[0];
        cmdLine_->command     = isAllowedCommand(candidate);
        if (cmdLine_->command == CommandKind::Invalid)
        {
            if (isSwagScriptPath(fs::path(candidate.c_str())))
            {
                configureScriptCommand(*cmdLine_, fs::path(candidate.c_str()));
                command_      = commandName(cmdLine_->command);
                argStartIndex = 1;
            }
            else
            {
                Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_command);
                setReportArguments(diag, candidate);
                diag.addArgument(Diagnostic::ARG_VALUES, getAllowedCommands());
                diag.addDidYouMeanNote(suggestCommand(candidate));
                diag.report(ctx);
                return Result::Error;
            }
        }
        else
        {
            cmdLine_->commandExplicit = true;
            command_                  = candidate;
            argStartIndex             = 1;
        }
    }
    else if (cmdLine_->commandExplicit)
    {
        command_ = commandName(cmdLine_->command);
    }
    else
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_command);
        diag.report(ctx);
        return Result::Error;
    }

    bool endOfOptions = false;
    for (size_t i = argStartIndex; i < args.size(); i++)
    {
        const Utf8& raw = args[i];

        // `--` stops option processing. Anything after is positional, which we do not accept.
        if (!endOfOptions && raw == END_OF_OPTIONS)
        {
            endOfOptions = true;
            continue;
        }

        if (endOfOptions)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_unexpected_positional);
            setReportArguments(diag, raw);
            diag.report(ctx);
            return Result::Error;
        }

        // Support `--long=value` and `-s=value`. Split once on the first '='.
        Utf8                lookup = raw;
        std::optional<Utf8> inlineValue;
        splitInlineOptionValue(raw, lookup, inlineValue);

        bool           invertBoolean = false;
        const ArgInfo* info          = findArgument(ctx, lookup, invertBoolean);
        if (!info)
        {
            if (!errorRaised_)
                reportInvalidArgument(ctx, raw);
            return Result::Error;
        }

        if (!commandMatches(info->commands))
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_cmd_arg);
            setReportArguments(diag, *info, raw);
            diag.report(ctx);
            return Result::Error;
        }

        const Utf8* inlinePtr = inlineValue.has_value() ? &inlineValue.value() : nullptr;
        if (!processArgument(ctx, *info, raw, invertBoolean, inlinePtr, i, args))
            return Result::Error;
    }

    return checkCommandLine(ctx);
}

Result CommandLineParser::checkCommandLine(TaskContext& ctx) const
{
    if (cmdLine_->command == CommandKind::Test)
    {
        struct StageOption
        {
            bool             enabled;
            std::string_view name;
        };

        const StageOption options[] = {
            {cmdLine_->lexOnly, "--lex-only"},
            {cmdLine_->syntaxOnly, "--syntax-only"},
            {cmdLine_->semaOnly, "--sema-only"},
        };

        std::string_view selectedArg;
        for (const auto& option : options)
        {
            if (!option.enabled)
                continue;

            if (selectedArg.empty())
            {
                selectedArg = option.name;
                continue;
            }

            return reportConflictingArgument(ctx, option.name, selectedArg);
        }
    }

    if (!cmdLine_->verboseVerifyFilter.empty())
        cmdLine_->verboseVerify = true;

    if (cmdLine_->devFull)
    {
#if SWC_HAS_VALIDATE_MICRO
        cmdLine_->validateMicro = true;
#endif
#if SWC_HAS_VALIDATE_NATIVE
        cmdLine_->validateNative = true;
#endif
    }

#if SWC_DEV_MODE
    if (cmdLine_->randSeed)
        cmdLine_->randomize = true;

    if (cmdLine_->randomize)
        cmdLine_->numCores = 1;
#endif

    if (!cmdLine_->moduleFilePath.empty())
    {
        fs::path temp = cmdLine_->moduleFilePath;
        SWC_RESULT(FileSystem::resolveFile(ctx, temp));
        cmdLine_->moduleFilePath = std::move(temp);
    }

    // Module path should exist
    if (!cmdLine_->modulePath.empty())
    {
        fs::path temp = cmdLine_->modulePath;
        SWC_RESULT(FileSystem::resolveFolder(ctx, temp));
        cmdLine_->modulePath = std::move(temp);
    }

    if (!cmdLine_->moduleFilePath.empty())
    {
        const fs::path derivedModulePath = cmdLine_->moduleFilePath.parent_path().lexically_normal();
        if (!cmdLine_->modulePath.empty() && !FileSystem::pathEquals(cmdLine_->modulePath, derivedModulePath))
            return reportConflictingArgument(ctx, "--module-file", "--module");

        cmdLine_->modulePath = derivedModulePath;
        if (cmdLine_->scriptMode)
        {
            cmdLine_->files.clear();
            cmdLine_->files.insert(cmdLine_->moduleFilePath);
        }
    }

    if (!cmdLine_->workspacePath.empty())
    {
        fs::path temp = cmdLine_->workspacePath;
        SWC_RESULT(FileSystem::resolveFolder(ctx, temp));
        cmdLine_->workspacePath = std::move(temp);
    }

    if (!cmdLine_->workspaceModuleFilter.empty() && cmdLine_->workspacePath.empty())
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_workspace_module_requires_workspace);
        diag.addArgument(Diagnostic::ARG_ARG, "--workspace-module");
        diag.report(ctx);
        return Result::Error;
    }

    if (!cmdLine_->workspacePath.empty())
    {
        if (!cmdLine_->moduleFilePath.empty())
            return reportConflictingArgument(ctx, "--workspace", "--module-file");
        if (!cmdLine_->modulePath.empty())
            return reportConflictingArgument(ctx, "--workspace", "--module");
        if (!cmdLine_->directories.empty())
            return reportConflictingArgument(ctx, "--workspace", "--directory");
        if (!cmdLine_->files.empty())
            return reportConflictingArgument(ctx, "--workspace", "--file");
        if (!cmdLine_->outDir.empty())
            return reportConflictingArgument(ctx, "--workspace", "--out-dir");
        if (!cmdLine_->workDir.empty())
            return reportConflictingArgument(ctx, "--workspace", "--work-dir");
        if (!cmdLine_->exportApiDir.empty())
            return reportConflictingArgument(ctx, "--workspace", "--export-api-dir");
    }

    const fs::path inputBaseDir = commandInputBaseDir(*cmdLine_);

    SWC_RESULT(resolveInputPathSet(ctx, inputBaseDir, cmdLine_->directories, FileSystem::resolveFolder));
    SWC_RESULT(resolveInputPathSet(ctx, inputBaseDir, cmdLine_->files, FileSystem::resolveFile));
    SWC_RESULT(resolveInputPathSet(ctx, inputBaseDir, cmdLine_->importApiDirs, FileSystem::resolveFolder));
    SWC_RESULT(resolveInputPathSet(ctx, inputBaseDir, cmdLine_->importApiFiles, FileSystem::resolveFile));

    if (!cmdLine_->scriptMode &&
        cmdLine_->command == CommandKind::Run &&
        cmdLine_->moduleFilePath.empty() &&
        cmdLine_->modulePath.empty() &&
        cmdLine_->workspacePath.empty() &&
        cmdLine_->directories.empty() &&
        cmdLine_->files.size() == 1 &&
        isSwagScriptPath(*cmdLine_->files.begin()))
    {
        cmdLine_->scriptMode     = true;
        cmdLine_->moduleFilePath = *cmdLine_->files.begin();
        cmdLine_->modulePath     = cmdLine_->moduleFilePath.parent_path().lexically_normal();
    }

    if (!cmdLine_->configFile.empty())
    {
        fs::path temp = cmdLine_->configFile;
        SWC_RESULT(FileSystem::resolveFile(ctx, temp));
        cmdLine_->configFile = std::move(temp);
    }

    SWC_RESULT(normalizeAbsoluteDirectory(ctx, cmdLine_->outDir, &cmdLine_->outDirStorage));
    SWC_RESULT(normalizeAbsoluteDirectory(ctx, cmdLine_->workDir, &cmdLine_->workDirStorage));
    SWC_RESULT(normalizeAbsoluteDirectory(ctx, cmdLine_->exportApiDir));

    updateDefaultBuildCfg(*cmdLine_);

    return Result::Continue;
}

CommandLineParser::CommandLineParser(Global& global, CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global)
{
    updateDefaultBuildCfg(*cmdLine_);
    registerCommands();
}

SWC_END_NAMESPACE();
