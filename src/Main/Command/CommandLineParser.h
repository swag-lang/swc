#pragma once

SWC_BEGIN_NAMESPACE();

class Diagnostic;
class TaskContext;
struct CommandLine;
class Global;
enum class CommandKind;

enum class HelpOptionGroup : uint8_t
{
    Input,
    Target,
    Compiler,
    Diagnostics,
    Logging,
    Testing,
    Development,
    Other
};

struct EnumIntTarget
{
    void (*setter)(void*, int) = nullptr;
    int (*getter)(const void*) = nullptr;
    void* target               = nullptr;
};

using ArgTarget = std::variant<
    bool*,
    int*,
    uint32_t*,
    Utf8*,
    fs::path*,
    std::vector<Utf8>*,
    std::set<Utf8>*,
    std::set<fs::path>*,
    std::optional<bool>*,
    EnumIntTarget>;

struct ArgInfo
{
    Utf8              commands;
    Utf8              longForm;
    Utf8              shortForm;
    ArgTarget         target = static_cast<bool*>(nullptr);
    std::vector<Utf8> choices;         // for EnumString and EnumInt: validated choice names
    std::vector<int>  choiceIntValues; // only for EnumInt: parallel to choices
    Utf8              description;
    HelpOptionGroup   group = HelpOptionGroup::Other;

    bool isEnum() const { return !choices.empty(); }
    bool isEnumInt() const { return std::holds_alternative<EnumIntTarget>(target); }
    bool isBoolLike() const
    {
        return std::holds_alternative<bool*>(target) ||
               std::holds_alternative<std::optional<bool>*>(target);
    }
};

class CommandLineParser
{
public:
    explicit CommandLineParser(Global& global, CommandLine& cmdLine);
    static void refreshBuildCfg(CommandLine& cmdLine);
    Result      parse(int argc, char* argv[]);

private:
    template<typename E>
    static void setEnumIntValue(void* target, int value)
    {
        *static_cast<E*>(target) = static_cast<E>(value);
    }

    template<typename E>
    static int getEnumIntValue(const void* target)
    {
        return static_cast<int>(*static_cast<const E*>(target));
    }

    std::vector<ArgInfo>   args_;
    std::map<Utf8, size_t> longFormMap_;
    std::map<Utf8, size_t> shortFormMap_;
    CommandLine*           cmdLine_     = nullptr;
    Global*                global_      = nullptr;
    bool                   errorRaised_ = false;
    Utf8                   command_;

    void                       printHelp(const TaskContext& ctx, const Utf8& command = "");
    static CommandKind         isAllowedCommand(const Utf8& cmd);
    static Utf8                getAllowedCommands();
    void                       setReportArguments(Diagnostic& diag, const Utf8& arg);
    void                       setReportArguments(Diagnostic& diag, const ArgInfo& info, const Utf8& arg);
    bool                       getNextValue(TaskContext& ctx, const Utf8& arg, const Utf8* inlineValue, size_t& index, const std::vector<Utf8>& args, Utf8& value);
    static Result              expandResponseFiles(TaskContext& ctx, const std::vector<Utf8>& in, std::vector<Utf8>& out);
    static Result              expandOneResponseFile(TaskContext& ctx, const fs::path& path, std::vector<Utf8>& out, std::set<fs::path>& visited, uint32_t depth);
    bool                       commandMatches(const Utf8& commandList) const;
    bool                       parseEnumString(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, Utf8* target);
    bool                       parseEnumInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, const EnumIntTarget& target);
    bool                       parseInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, int* out);
    bool                       parseUInt(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value, uint32_t* out);
    const ArgInfo*             findArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean);
    const ArgInfo*             findLongFormArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean);
    const ArgInfo*             findShortFormArgument(const TaskContext& ctx, const Utf8& arg);
    const ArgInfo*             findNegatedArgument(TaskContext& ctx, const Utf8& arg, bool& invertBoolean);
    void                       reportInvalidArgument(TaskContext& ctx, const Utf8& arg);
    static void                attachSuggestion(Diagnostic& diag, std::optional<Utf8> suggestion);
    std::optional<Utf8>        suggestArgument(const Utf8& query) const;
    static std::optional<Utf8> suggestCommand(const Utf8& query);
    static std::optional<Utf8> suggestChoice(const Utf8& query, const std::vector<Utf8>& choices);
    bool                       processArgument(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, bool invertBoolean, const Utf8* inlineValue, size_t& index, const std::vector<Utf8>& args);
    bool                       reportEnumError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value);
    bool                       reportIntError(TaskContext& ctx, const ArgInfo& info, const Utf8& arg, const Utf8& value);
    Result                     checkCommandLine(TaskContext& ctx) const;

    ArgInfo& addImpl(HelpOptionGroup group, const char* commands, const char* longForm, const char* shortForm, const char* description, const ArgTarget& target);

    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, bool* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, int* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, uint32_t* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, Utf8* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, fs::path* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::vector<Utf8>* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::set<Utf8>* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::set<fs::path>* target, const char* desc);
    void add(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, std::optional<bool>* target, const char* desc);

    void addEnum(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, Utf8* target, std::vector<Utf8> choices, const char* desc);

    template<typename E>
    void addEnum(HelpOptionGroup g, const char* cmds, const char* lf, const char* sf, E* target, std::initializer_list<std::pair<const char*, E>> choices, const char* desc)
    {
        EnumIntTarget et;
        et.target = target;
        et.setter = &CommandLineParser::setEnumIntValue<E>;
        et.getter = &CommandLineParser::getEnumIntValue<E>;

        ArgInfo& info = addImpl(g, cmds, lf, sf, desc, et);
        for (const auto& [name, val] : choices)
        {
            info.choices.emplace_back(name);
            info.choiceIntValues.push_back(static_cast<int>(val));
        }
    }
};

SWC_END_NAMESPACE();
