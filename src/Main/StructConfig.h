#pragma once
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

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

    static void setBoolTrue(void* data)
    {
        *static_cast<bool*>(data) = true;
    }

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
    std::string_view       name;
    StructConfigTarget     target = static_cast<bool*>(nullptr);
    std::vector<Utf8>      choices;
    std::vector<int>       choiceIntValues;
    std::string_view       description;
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
    StructConfigSchema() { entries_.reserve(64); }

    StructConfigEntry& add(std::string_view name, const StructConfigTarget& target, std::string_view description = {}, StructConfigAssignHook hook = {});
    StructConfigEntry& addEnum(std::string_view name, Utf8* target, std::vector<Utf8> choices, std::string_view description = {}, StructConfigAssignHook hook = {});

    template<typename T>
    StructConfigEntry& add(std::string_view name, T* target, std::string_view description = {}, StructConfigAssignHook hook = {})
    {
        return addImpl(name, description, target, hook);
    }

    template<typename E>
    StructConfigEntry& addEnum(std::string_view name, E* target, std::initializer_list<std::pair<const char*, E>> choices, std::string_view description = {}, StructConfigAssignHook hook = {})
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

    StructConfigEntry& addImpl(std::string_view name, std::string_view description, const StructConfigTarget& target, StructConfigAssignHook hook);

    std::vector<StructConfigEntry> entries_;
};

class StructConfigReader
{
public:
    explicit StructConfigReader(const StructConfigSchema& schema);
    Result readFile(TaskContext& ctx, const fs::path& path) const;

private:
    const StructConfigSchema* schema_ = nullptr;

    static bool   parseBool(std::string_view value, bool& result);
    static Utf8   stripInlineComment(std::string_view line, bool& unterminatedQuote);
    static size_t findAssignment(std::string_view line);

    static bool applyEntry(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, uint32_t lineNo, std::string_view valueText, const fs::path& baseDir);
    bool        reportUnknownKey(TaskContext& ctx, const fs::path& sourcePath, uint32_t lineNo, const Utf8& key) const;
    static bool reportInvalidEnum(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, uint32_t lineNo, const Utf8& value);
};

SWC_END_NAMESPACE();
