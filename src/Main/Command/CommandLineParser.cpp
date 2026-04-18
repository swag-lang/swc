#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
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
    std::optional<Utf8> bestMatch(std::string_view query, const std::vector<Utf8>& candidates)
    {
        if (candidates.empty() || query.length() < 3)
            return std::nullopt;

        const size_t maxDist = std::max<size_t>(1, std::min<size_t>(3, query.length() / 3));

        size_t      bestDist = std::numeric_limits<size_t>::max();
        const Utf8* best     = nullptr;
        for (const Utf8& c : candidates)
        {
            const size_t d = Utf8Helper::levenshtein(query, c);
            if (d < bestDist)
            {
                bestDist = d;
                best     = &c;
            }
        }

        if (!best || bestDist > maxDist)
            return std::nullopt;
        return *best;
    }

    constexpr uint32_t RSP_MAX_DEPTH = 16;

    // Split response-file content into whitespace-separated tokens.
    // Supports `"..."` and `'...'` for tokens containing spaces. No escape sequences.
    // Returns false if a quote is left unterminated.
    bool tokenizeResponseFile(std::string_view content, std::vector<Utf8>& out)
    {
        Utf8 token;
        char quote = 0;
        bool inTok = false;

        auto flush = [&] {
            if (inTok || quote)
            {
                out.push_back(std::move(token));
                inTok = false;
            }
        };

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
                flush();
                continue;
            }

            token.push_back(c);
            inTok = true;
        }

        if (quote)
            return false;

        flush();
        return true;
    }

    std::vector<Utf8> splitPipe(std::string_view s)
    {
        std::vector<Utf8> out;
        if (s.empty())
            return out;

        size_t start = 0;
        while (start <= s.size())
        {
            size_t end = s.find('|', start);
            if (end == std::string_view::npos)
                end = s.size();
            out.emplace_back(s.substr(start, end - start));
            if (end == s.size())
                break;
            start = end + 1;
        }
        return out;
    }

    bool validateStageSelection(TaskContext& ctx, const CommandLine& cmdLine)
    {
        struct StageOption
        {
            bool             enabled;
            std::string_view name;
        };

        const StageOption options[] = {
            {cmdLine.lexOnly, "--lex-only"},
            {cmdLine.syntaxOnly, "--syntax-only"},
            {cmdLine.semaOnly, "--sema-only"},
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

            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_conflicting_arg);
            diag.addArgument(Diagnostic::ARG_ARG, option.name);
            diag.addArgument(Diagnostic::ARG_VALUE, selectedArg);
            diag.report(ctx);
            return false;
        }

        return true;
    }

    std::string_view registeredBuildCfgsView(const Runtime::BuildCfg& buildCfg)
    {
        if (!buildCfg.registeredConfigs.ptr || !buildCfg.registeredConfigs.length)
            return {};

        return {buildCfg.registeredConfigs.ptr, buildCfg.registeredConfigs.length};
    }

    bool hasRegisteredBuildCfg(const Runtime::BuildCfg& buildCfg, const std::string_view cfgName)
    {
        if (cfgName.empty())
            return false;

        const std::string_view registered = registeredBuildCfgsView(buildCfg);
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

    bool applyBuildCfgPreset(Runtime::BuildCfg& buildCfg, const std::string_view cfgName)
    {
        if (cfgName == "fast-compile")
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::None;
            buildCfg.sanity            = false;
            buildCfg.errorStackTrace   = false;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = false;
            buildCfg.backend.debugInfo = false;
        }
        else if (cfgName == "debug")
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::All;
            buildCfg.sanity            = true;
            buildCfg.errorStackTrace   = true;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = false;
            buildCfg.backend.debugInfo = true;
        }
        else if (cfgName == "fast-debug")
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::All;
            buildCfg.sanity            = true;
            buildCfg.errorStackTrace   = true;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = true;
            buildCfg.backend.debugInfo = true;
        }
        else if (cfgName == "release")
        {
            buildCfg.safetyGuards               = Runtime::SafetyWhat::None;
            buildCfg.sanity                     = false;
            buildCfg.errorStackTrace            = false;
            buildCfg.debugAllocator             = false;
            buildCfg.backend.optimize           = true;
            buildCfg.backend.debugInfo          = true;
            buildCfg.backend.fpMathFma          = true;
            buildCfg.backend.fpMathNoNaN        = true;
            buildCfg.backend.fpMathNoInf        = true;
            buildCfg.backend.fpMathNoSignedZero = true;
        }
        else
        {
            return false;
        }

        return true;
    }

    void updateDefaultBuildCfg(CommandLine& cmdLine)
    {
        Runtime::BuildCfg buildCfg{};
        if (cmdLine.defaultBuildCfg.registeredConfigs.ptr && cmdLine.defaultBuildCfg.registeredConfigs.length)
            buildCfg.registeredConfigs = cmdLine.defaultBuildCfg.registeredConfigs;

        SWC_ASSERT(hasRegisteredBuildCfg(buildCfg, cmdLine.buildCfg.view()));
        SWC_INTERNAL_CHECK(applyBuildCfgPreset(buildCfg, cmdLine.buildCfg.view()));

        if (cmdLine.backendOptimize.has_value())
            buildCfg.backend.optimize = cmdLine.backendOptimize.value();

        buildCfg.backendKind = cmdLine.backendKind;

        if (cmdLine.isTestMode())
        {
            buildCfg.backend.debugInfo        = true;
            buildCfg.backend.enableExceptions = true;
        }

        cmdLine.moduleNamespaceStorage = cmdLine.moduleNamespace;
        if (cmdLine.moduleNamespaceStorage.empty())
            cmdLine.moduleNamespaceStorage = commandLineDefaultModuleNamespace(commandLineDefaultArtifactName(cmdLine));

        buildCfg.moduleNamespace = Utf8Helper::runtimeStringFromUtf8(cmdLine.moduleNamespaceStorage);
        buildCfg.name           = Utf8Helper::runtimeStringFromUtf8(cmdLine.name);
        buildCfg.outDir         = Utf8Helper::runtimeStringFromUtf8(cmdLine.outDirStorage);
        buildCfg.workDir        = Utf8Helper::runtimeStringFromUtf8(cmdLine.workDirStorage);
        cmdLine.defaultBuildCfg = buildCfg;
    }
}

void CommandLineParser::refreshBuildCfg(CommandLine& cmdLine)
{
    updateDefaultBuildCfg(cmdLine);
}

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
    if (depth >= RSP_MAX_DEPTH)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_depth);
        diag.addArgument(Diagnostic::ARG_PATH, Utf8(path));
        diag.report(ctx);
        return Result::Error;
    }

    std::error_code ec;
    fs::path        canonical = fs::weakly_canonical(path, ec);
    if (ec)
        canonical = fs::absolute(path, ec);

    if (!visited.insert(canonical).second)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_cycle);
        diag.addArgument(Diagnostic::ARG_PATH, Utf8(path));
        diag.report(ctx);
        return Result::Error;
    }

    std::ifstream file(canonical, std::ios::binary);
    if (!file)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_failed);
        diag.addArgument(Diagnostic::ARG_PATH, Utf8(path));
        diag.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(std::make_error_code(std::errc::no_such_file_or_directory)));
        diag.report(ctx);
        return Result::Error;
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    const std::string content = buffer.str();

    std::vector<Utf8> tokens;
    if (!tokenizeResponseFile(content, tokens))
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_rsp_file_unterminated);
        diag.addArgument(Diagnostic::ARG_PATH, Utf8(path));
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

bool CommandLineParser::parseInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* out)
{
    const char* first    = value.data();
    const char* last     = first + value.size();
    int         tmp      = 0;
    const auto [ptr, ec] = std::from_chars(first, last, tmp);
    if (ec != std::errc{} || ptr != last || value.empty())
        return reportIntError(ctx, info, arg, value);

    *out = tmp;
    return true;
}

bool CommandLineParser::parseUInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, uint32_t* out)
{
    const char* first    = value.data();
    const char* last     = first + value.size();
    uint32_t    tmp      = 0;
    const auto [ptr, ec] = std::from_chars(first, last, tmp);
    if (ec != std::errc{} || ptr != last || value.empty())
        return reportIntError(ctx, info, arg, value);

    *out = tmp;
    return true;
}

bool CommandLineParser::reportEnumError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_enum);
    setReportArguments(diag, info, arg);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    attachSuggestion(diag, suggestChoice(value, info.choices));
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

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, bool* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, int* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, uint32_t* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, Utf8* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, fs::path* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::vector<Utf8>* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::set<Utf8>* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::set<fs::path>* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::optional<bool>* target, const char* desc)
{
    addImpl(g, cmds, lf, sf, desc, target);
}

void CommandLineParser::addEnum(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, Utf8* target, std::vector<Utf8> choices, const char* desc)
{
    ArgInfo& info = addImpl(g, cmds, lf, sf, desc, target);
    info.choices  = std::move(choices);
}

const ArgInfo* CommandLineParser::findArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean)
{
    invertBoolean = false;

    if (arg.substr(0, LONG_PREFIX_LEN) == LONG_PREFIX)
        return findLongFormArgument(ctx, arg, invertBoolean);
    if (arg.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX && arg.length() > SHORT_PREFIX_LEN)
        return findShortFormArgument(ctx, arg);

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

const ArgInfo* CommandLineParser::findShortFormArgument(const TaskContext& ctx, const Utf8& arg)
{
    SWC_UNUSED(ctx);
    const auto it = shortFormMap_.find(arg);
    if (it != shortFormMap_.end())
        return &args_[it->second];
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
    attachSuggestion(diag, suggestArgument(arg));
    diag.report(ctx);
}

void CommandLineParser::attachSuggestion(Diagnostic& diag, std::optional<Utf8> suggestion)
{
    if (!suggestion.has_value())
        return;

    // Bind {value} on the note element itself so it wins over any {value} the
    // parent diagnostic already has (e.g. the invalid enum input).
    DiagnosticElement& note = diag.addElement(DiagnosticId::cmd_note_did_you_mean);
    note.setSeverity(DiagnosticSeverity::Note);
    note.addArgument(Diagnostic::ARG_VALUE, suggestion.value());
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
    return bestMatch(query, candidates);
}

std::optional<Utf8> CommandLineParser::suggestCommand(const Utf8& query)
{
    std::vector<Utf8> candidates;
    candidates.reserve(std::size(COMMANDS));
    for (const CommandInfo& cmd : COMMANDS)
        candidates.emplace_back(cmd.name);
    return bestMatch(query, candidates);
}

std::optional<Utf8> CommandLineParser::suggestChoice(const Utf8& query, const std::vector<Utf8>& choices)
{
    return bestMatch(query, choices);
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
        return parseInt(ctx, info, arg, value, *t);
    if (auto* t = std::get_if<uint32_t*>(&info.target))
        return parseUInt(ctx, info, arg, value, *t);
    if (auto* t = std::get_if<Utf8*>(&info.target))
    {
        if (info.isEnum())
            return parseEnumString(ctx, info, arg, value, *t);
        **t = value;
        return true;
    }
    if (auto* t = std::get_if<fs::path*>(&info.target))
    {
        **t = value.c_str();
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
        if (parsed && t->target == &cmdLine_->backendKind)
            cmdLine_->artifactKindExplicit = true;
        return parsed;
    }

    SWC_UNREACHABLE();
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
            attachSuggestion(diag, suggestCommand(command));
            diag.report(ctx);
            return Result::Error;
        }

        parser.printHelp(ctx, command);
        return Result::Error;
    }

    // Require a command as the first positional token (no leading '-').
    if (argc <= 1 || argv[1][0] == '-')
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_missing_command);
        diag.report(ctx);
        return Result::Error;
    }

    // Validate and set the command.
    {
        const Utf8 candidate = argv[1];
        cmdLine_->command    = isAllowedCommand(candidate);
        if (cmdLine_->command == CommandKind::Invalid)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_command);
            setReportArguments(diag, argv[1]);
            diag.addArgument(Diagnostic::ARG_VALUES, getAllowedCommands());
            attachSuggestion(diag, suggestCommand(candidate));
            diag.report(ctx);
            return Result::Error;
        }

        command_ = candidate;
    }

    std::vector<Utf8> rawArgs;
    rawArgs.reserve(static_cast<size_t>(argc) - 2);
    for (int i = 2; i < argc; i++)
        rawArgs.emplace_back(argv[i]);

    std::vector<Utf8> args;
    SWC_RESULT(expandResponseFiles(ctx, rawArgs, args));

    bool endOfOptions = false;
    for (size_t i = 0; i < args.size(); i++)
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
        if (raw.substr(0, SHORT_PREFIX_LEN) == SHORT_PREFIX)
        {
            const size_t eq = raw.find('=');
            if (eq != Utf8::npos)
            {
                lookup      = raw.substr(0, eq);
                inlineValue = raw.substr(eq + 1);
            }
        }

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
    if (cmdLine_->isTestCommand())
        cmdLine_->sourceDrivenTest = true;

    if (cmdLine_->isTestCommand() && !validateStageSelection(ctx, *cmdLine_))
        return Result::Error;

    if (!cmdLine_->verboseVerifyFilter.empty())
        cmdLine_->verboseVerify = true;

    if (cmdLine_->devFull)
    {
#if SWC_HAS_UNITTEST
        cmdLine_->unittest = true;
#endif
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

    // Resolve all folders
    std::set<fs::path> resolvedFolders;
    for (const fs::path& folder : cmdLine_->directories)
    {
        fs::path temp = folder;
        SWC_RESULT(FileSystem::resolveFolder(ctx, temp));
        resolvedFolders.insert(std::move(temp));
    }
    cmdLine_->directories = std::move(resolvedFolders);

    // Resolve all files
    std::set<fs::path> resolvedFiles;
    for (const fs::path& file : cmdLine_->files)
    {
        fs::path temp = file;
        SWC_RESULT(FileSystem::resolveFile(ctx, temp));
        resolvedFiles.insert(std::move(temp));
    }
    cmdLine_->files = std::move(resolvedFiles);

    // Module path should exist
    if (!cmdLine_->modulePath.empty())
    {
        fs::path temp = cmdLine_->modulePath;
        SWC_RESULT(FileSystem::resolveFolder(ctx, temp));
        cmdLine_->modulePath = std::move(temp);
    }

    cmdLine_->originalDirectories = cmdLine_->directories;
    cmdLine_->originalFiles       = cmdLine_->files;
    cmdLine_->originalModulePath  = cmdLine_->modulePath;

    if (!cmdLine_->outDir.empty())
    {
        std::error_code ec;
        fs::path        temp = fs::absolute(cmdLine_->outDir, ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(cmdLine_->outDir));
            diag.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        cmdLine_->outDir        = std::move(temp);
        cmdLine_->outDirStorage = Utf8(cmdLine_->outDir);
    }
    else
    {
        cmdLine_->outDirStorage.clear();
    }

    if (!cmdLine_->workDir.empty())
    {
        std::error_code ec;
        fs::path        temp = fs::absolute(cmdLine_->workDir, ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(cmdLine_->workDir));
            diag.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        cmdLine_->workDir        = std::move(temp);
        cmdLine_->workDirStorage = Utf8(cmdLine_->workDir);
    }
    else
    {
        cmdLine_->workDirStorage.clear();
    }

    updateDefaultBuildCfg(*cmdLine_);

    return Result::Continue;
}

CommandLineParser::CommandLineParser(Global& global, CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global)
{
    updateDefaultBuildCfg(*cmdLine_);
    const std::string_view registeredBuildCfgs{cmdLine_->defaultBuildCfg.registeredConfigs.ptr, cmdLine_->defaultBuildCfg.registeredConfigs.length};

    add(HelpOptionGroup::Input, "all", "--directory", "-d",
        &cmdLine_->directories,
        "Specify one or more directories to process recursively for input files.");
    add(HelpOptionGroup::Input, "all", "--file", "-f",
        &cmdLine_->files,
        "Specify one or more individual files to process directly.");
    add(HelpOptionGroup::Input, "all", "--file-filter", "-ff",
        &cmdLine_->fileFilter,
        "Apply a substring filter to input paths.");
    add(HelpOptionGroup::Input, "all", "--module", "-m",
        &cmdLine_->modulePath,
        "Specify a module path to compile.");
    add(HelpOptionGroup::Input, "all", "--runtime", "-rt",
        &cmdLine_->runtime,
        "Include runtime files in the input set.");

    addEnum(HelpOptionGroup::Target, "sema test build run", "--arch", "-a",
            &cmdLine_->targetArch,
            {
                {"x86_64", Runtime::TargetArch::X86_64},
            },
            "Set the target architecture used by #arch and compiler target queries.");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--build-cfg", "-bc",
            &cmdLine_->buildCfg,
            splitPipe(registeredBuildCfgs),
            "Set the registered build configuration string used by #cfg and @compiler.getBuildCfg().");
    addEnum(HelpOptionGroup::Target, "sema test build run", "--artifact-kind", "-ak",
            &cmdLine_->backendKind,
            {
                {"exe", Runtime::BuildCfgBackendKind::Executable},
                {"dll", Runtime::BuildCfgBackendKind::SharedLibrary},
                {"lib", Runtime::BuildCfgBackendKind::StaticLibrary},
            },
            "Select the native artifact kind exposed through @compiler.getBuildCfg() and used by the native backend.");
    add(HelpOptionGroup::Target, "sema test build run", "--cpu", "-cpu",
        &cmdLine_->targetCpu,
        "Set the target CPU string used by #cpu and compiler target queries.");
    add(HelpOptionGroup::Target, "sema test build run", "--artifact-name", "-n",
        &cmdLine_->name,
        "Set the artifact name exposed through @compiler.getBuildCfg() and used for native outputs.");
    add(HelpOptionGroup::Target, "sema test build run", "--module-namespace", nullptr,
        &cmdLine_->moduleNamespace,
        "Force the module namespace name exposed through @compiler.getBuildCfg() and used as the semantic module root.");
    add(HelpOptionGroup::Target, "sema test build run", "--out-dir", "-od",
        &cmdLine_->outDir,
        "Set the artifact output directory exposed through @compiler.getBuildCfg().");
    add(HelpOptionGroup::Target, "sema test build run", "--work-dir", "-wd",
        &cmdLine_->workDir,
        "Set the work directory exposed through @compiler.getBuildCfg().");
    add(HelpOptionGroup::Target, "sema test build run", "--optimize", "-o",
        &cmdLine_->backendOptimize,
        "Enable backend optimization for JIT folding and native code generation.");

    add(HelpOptionGroup::Compiler, "all", "--num-cores", "-j",
        &cmdLine_->numCores,
        "Set the maximum number of CPU cores to use (0 = auto-detect).");
    add(HelpOptionGroup::Compiler, "all", "--stats", "-st",
        &cmdLine_->stats,
        "Display runtime statistics after execution.");
    add(HelpOptionGroup::Compiler, "all", "--stats-mem", "-stm",
        &cmdLine_->statsMem,
        "Display runtime memory statistics after execution.");
    add(HelpOptionGroup::Compiler, "sema test build run", "--tag", nullptr,
        &cmdLine_->tags,
        "Register a compiler tag consumed by #hastag and #gettag. Syntax: Name, Name = value, or Name: type = value.");
    add(HelpOptionGroup::Compiler, "test build run", "--clear-output", "-co",
        &cmdLine_->clear,
        "Clear native work and artifact folders before building native outputs.");

    addEnum<FileSystem::FilePathDisplayMode>(
        HelpOptionGroup::Diagnostics, "all", "--path-display", "-pd",
        &cmdLine_->filePathDisplay,
        {
            {"as-is", FileSystem::FilePathDisplayMode::AsIs},
            {"basename", FileSystem::FilePathDisplayMode::BaseName},
            {"absolute", FileSystem::FilePathDisplayMode::Absolute},
        },
        "Control file path display style for diagnostics, stack traces and file locations.");
    add(HelpOptionGroup::Diagnostics, "all", "--diagnostic-id", "-di",
        &cmdLine_->errorId,
        "Show diagnostic identifiers.");
    add(HelpOptionGroup::Diagnostics, "all", "--diagnostic-one-line", "-dl",
        &cmdLine_->diagOneLine,
        "Display diagnostics as a single line.");

    add(HelpOptionGroup::Logging, "all", "--log-ascii", "-la",
        &cmdLine_->logAscii,
        "Restrict console output to ASCII characters (disable Unicode).");
    add(HelpOptionGroup::Logging, "all", "--log-color", "-lc",
        &cmdLine_->logColor,
        "Enable colored log output for better readability.");
    add(HelpOptionGroup::Logging, "all", "--silent", "-s",
        &cmdLine_->silent,
        "Suppress all log output.");
    add(HelpOptionGroup::Logging, "all", "--syntax-color", "-sc",
        &cmdLine_->syntaxColor,
        "Syntax color output code.");
    add(HelpOptionGroup::Logging, "all", "--syntax-color-lum", "-scl",
        &cmdLine_->syntaxColorLum,
        "Syntax color luminosity factor [0-100].");

    add(HelpOptionGroup::Testing, "test", "--test-native", "-tn",
        &cmdLine_->testNative,
        "Enable native backend testing for #test sources.");
    add(HelpOptionGroup::Testing, "test", "--test-jit", "-tj",
        &cmdLine_->testJit,
        "Enable JIT execution for #test functions during testing.");
    add(HelpOptionGroup::Testing, "test", "--lex-only", nullptr,
        &cmdLine_->lexOnly,
        "Stop test inputs after lexing. Cannot be combined with --syntax-only or --sema-only.");
    add(HelpOptionGroup::Testing, "test", "--syntax-only", nullptr,
        &cmdLine_->syntaxOnly,
        "Stop test inputs after parsing. Cannot be combined with --lex-only or --sema-only.");
    add(HelpOptionGroup::Testing, "test", "--sema-only", nullptr,
        &cmdLine_->semaOnly,
        "Stop test inputs after semantic analysis. Cannot be combined with --lex-only or --syntax-only.");
    add(HelpOptionGroup::Testing, "test", "--output", nullptr,
        &cmdLine_->output,
        "Enable native artifact generation during testing. Use --no-output to keep JIT-only test runs in-memory.");
    add(HelpOptionGroup::Testing, "test", "--verbose-verify", "-vv",
        &cmdLine_->verboseVerify,
        "Show diagnostics normally matched and suppressed by source-driven tests.");
    add(HelpOptionGroup::Testing, "test", "--verbose-verify-filter", "-vvf",
        &cmdLine_->verboseVerifyFilter,
        "Restrict --verbose-verify output to messages or diagnostic IDs matching a specific string.");

    add(HelpOptionGroup::Development, "all", "--dry-run", "-dr",
        &cmdLine_->dryRun,
        "Print computed command, environment, toolchain and native artifact information without running the command.");
    add(HelpOptionGroup::Development, "all", "--dev-stop", "-ds",
        &CompilerInstance::dbgDevStop,
        "Open a message box when an error is reported.");
    add(HelpOptionGroup::Development, "all", "--dev-full", "-df",
        &cmdLine_->devFull,
        "Force every compiled development test and validation.");

#if SWC_HAS_UNITTEST
    add(HelpOptionGroup::Development, "all", "--unittest", "-ut",
        &cmdLine_->unittest,
        "Run internal C++ unit tests before executing command.");
    add(HelpOptionGroup::Development, "all", "--verbose-unittest", "-vu",
        &cmdLine_->verboseUnittest,
        "Print each internal unit test status.");
#endif

#if SWC_HAS_VALIDATE_MICRO
    add(HelpOptionGroup::Development, "all", "--validate-micro", nullptr,
        &cmdLine_->validateMicro,
        "Run Micro IR legality and pass-invariant validation.");
#endif

#if SWC_HAS_VALIDATE_NATIVE
    add(HelpOptionGroup::Development, "all", "--validate-native", nullptr,
        &cmdLine_->validateNative,
        "Run native backend validation, including constant relocation validation.");
#endif

#if SWC_DEV_MODE
    add(HelpOptionGroup::Development, "all", "--randomize", "-rz",
        &cmdLine_->randomize,
        "Randomize single-threaded job scheduling. Forces --num-cores=1.");
    add(HelpOptionGroup::Development, "all", "--seed", "-rs",
        &cmdLine_->randSeed,
        "Set the seed for --randomize. Forces --randomize and --num-cores=1.");
#endif
}

SWC_END_NAMESPACE();
