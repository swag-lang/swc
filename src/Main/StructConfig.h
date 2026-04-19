#pragma once

SWC_BEGIN_NAMESPACE();

class Diagnostic;
class TaskContext;

struct StructConfigEnumIntTarget
{
    void (*setter)(void*, int) = nullptr;
    int (*getter)(const void*) = nullptr;
    void* target               = nullptr;
};

struct StructConfigAssignHook
{
    void (*fn)(void*) = nullptr;
    void* data        = nullptr;

    void invoke() const
    {
        if (fn)
            fn(data);
    }
};

using StructConfigTarget = std::variant<
    bool*,
    int*,
    uint32_t*,
    Utf8*,
    fs::path*,
    std::vector<Utf8>*,
    std::set<Utf8>*,
    std::set<fs::path>*,
    std::optional<bool>*,
    StructConfigEnumIntTarget>;

struct StructConfigEntry
{
    Utf8                   name;
    StructConfigTarget     target = static_cast<bool*>(nullptr);
    std::vector<Utf8>      choices;
    std::vector<int>       choiceIntValues;
    Utf8                   description;
    StructConfigAssignHook afterSet{};

    bool isEnum() const { return !choices.empty(); }
    bool isBoolLike() const
    {
        return std::holds_alternative<bool*>(target) ||
               std::holds_alternative<std::optional<bool>*>(target);
    }
};

class StructConfigSchema
{
public:
    StructConfigEntry& add(const char* name, const StructConfigTarget& target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, bool* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, int* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, uint32_t* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, Utf8* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, fs::path* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, std::vector<Utf8>* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, std::set<Utf8>* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, std::set<fs::path>* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& add(const char* name, std::optional<bool>* target, const char* description = nullptr, StructConfigAssignHook hook = {});
    StructConfigEntry& addEnum(const char* name, Utf8* target, std::vector<Utf8> choices, const char* description = nullptr, StructConfigAssignHook hook = {});

    template<typename E>
    StructConfigEntry& addEnum(const char* name, E* target, std::initializer_list<std::pair<const char*, E>> choices, const char* description = nullptr, StructConfigAssignHook hook = {})
    {
        StructConfigEnumIntTarget enumTarget;
        enumTarget.target = target;
        enumTarget.setter = &StructConfigSchema::setEnumIntValue<E>;
        enumTarget.getter = &StructConfigSchema::getEnumIntValue<E>;

        StructConfigEntry& entry = addImpl(name, description, enumTarget, hook);
        for (const auto& [choiceName, choiceValue] : choices)
        {
            entry.choices.emplace_back(choiceName);
            entry.choiceIntValues.push_back(static_cast<int>(choiceValue));
        }

        return entry;
    }

    const StructConfigEntry* find(std::string_view name) const;
    std::optional<Utf8>      suggest(std::string_view query) const;

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

    StructConfigEntry& addImpl(const char* name, const char* description, const StructConfigTarget& target, StructConfigAssignHook hook);

    std::vector<StructConfigEntry>      entries_;
    std::map<Utf8, size_t, std::less<>> entriesMap_;
};

class StructConfigReader
{
public:
    explicit StructConfigReader(const StructConfigSchema& schema);
    Result readFile(TaskContext& ctx, const fs::path& path) const;

    static std::optional<Utf8> bestMatch(std::string_view query, const std::vector<Utf8>& candidates);

private:
    const StructConfigSchema* schema_ = nullptr;

    static bool   parseBool(std::string_view value, bool& result);
    static bool   parseInt(std::string_view value, int& result);
    static bool   parseUInt(std::string_view value, uint32_t& result);
    static Utf8   stripInlineComment(std::string_view line, bool& unterminatedQuote);
    static size_t findAssignment(std::string_view line);
    static Utf8   unquoteValue(std::string_view value);
    static void   attachSuggestion(Diagnostic& diag, std::optional<Utf8> suggestion);

    bool applyEntry(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, uint32_t lineNo, std::string_view value, const fs::path& baseDir) const;
    bool reportUnknownKey(TaskContext& ctx, const fs::path& sourcePath, uint32_t lineNo, const Utf8& key) const;
    bool reportInvalidEntry(TaskContext& ctx, const fs::path& sourcePath, uint32_t lineNo, const Utf8& because) const;
    bool reportInvalidBool(TaskContext& ctx, const fs::path& sourcePath, uint32_t lineNo, const Utf8& key, const Utf8& value) const;
    bool reportInvalidInt(TaskContext& ctx, const fs::path& sourcePath, uint32_t lineNo, const Utf8& key, const Utf8& value) const;
    bool reportInvalidEnum(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, uint32_t lineNo, const Utf8& value) const;
};

SWC_END_NAMESPACE();
