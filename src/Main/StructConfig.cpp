#include "pch.h"
#include "Main/StructConfig.h"
#include "Main/FileSystem.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 formatConfigLocation(const TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo)
    {
        if (!lineNo)
            return FileSystem::formatDiagnosticPath(&ctx, sourcePath);
        return FileSystem::formatFileLocation(&ctx, sourcePath, lineNo);
    }

    template<typename T>
    bool parseIntegerValue(std::string_view value, T& result)
    {
        const char* first       = value.data();
        const char* last        = first + value.size();
        const auto [ptr, error] = std::from_chars(first, last, result);
        return !value.empty() && error == std::errc{} && ptr == last;
    }

    bool reportInvalidScalarValue(TaskContext& ctx, const DiagnosticId diagId, const StructConfigEntry& entry, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& value)
    {
        Diagnostic diag = Diagnostic::get(diagId);
        diag.addArgument(Diagnostic::ARG_ARG, entry.name);
        diag.addArgument(Diagnostic::ARG_VALUE, value);
        diag.addArgument(Diagnostic::ARG_PATH, formatConfigLocation(ctx, sourcePath, lineNo));
        diag.report(ctx);
        return false;
    }

    Result reportInvalidConfigEntry(TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo, const std::string_view because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_invalid_entry);
        diag.addArgument(Diagnostic::ARG_PATH, formatConfigLocation(ctx, sourcePath, lineNo));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.report(ctx);
        return Result::Error;
    }

    fs::path resolveConfigPathValue(const Utf8& value, const fs::path& baseDir)
    {
        fs::path path = value.c_str();
        if (!value.empty() && path.is_relative())
            path = (baseDir / path).lexically_normal();
        return path;
    }
}

StructConfigEntry& StructConfigSchema::addImpl(const char* name, const char* description, const StructConfigTarget& target, const StructConfigAssignHook hook)
{
    StructConfigEntry entry;
    entry.name        = name ? name : "";
    entry.description = description ? description : "";
    entry.target      = target;
    entry.afterSet    = hook;

    SWC_ASSERT(!entry.name.empty());
    SWC_ASSERT(!entriesMap_.contains(entry.name));

    const size_t index      = entries_.size();
    entriesMap_[entry.name] = index;
    entries_.push_back(std::move(entry));
    return entries_.back();
}

StructConfigEntry& StructConfigSchema::add(const char* name, const StructConfigTarget& target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::addEnum(const char* name, Utf8* target, std::vector<Utf8> choices, const char* description, const StructConfigAssignHook hook)
{
    StructConfigEntry& entry = addImpl(name, description, target, hook);
    entry.choices            = std::move(choices);
    return entry;
}

const StructConfigEntry* StructConfigSchema::find(const std::string_view name) const
{
    const auto it = entriesMap_.find(name);
    if (it == entriesMap_.end())
        return nullptr;

    return &entries_[it->second];
}

std::optional<Utf8> StructConfigSchema::suggest(const std::string_view query) const
{
    std::vector<Utf8> candidates;
    candidates.reserve(entries_.size());
    for (const StructConfigEntry& entry : entries_)
        candidates.push_back(entry.name);

    return Utf8Helper::bestMatch(query, candidates);
}

StructConfigReader::StructConfigReader(const StructConfigSchema& schema) :
    schema_(&schema)
{
}

bool StructConfigReader::parseBool(const std::string_view value, bool& result)
{
    Utf8 normalized = Utf8Helper::trim(value);
    normalized.make_lower();

    if (normalized == "true" || normalized == "yes" || normalized == "on" || normalized == "1")
    {
        result = true;
        return true;
    }

    if (normalized == "false" || normalized == "no" || normalized == "off" || normalized == "0")
    {
        result = false;
        return true;
    }

    return false;
}

Utf8 StructConfigReader::stripInlineComment(const std::string_view line, bool& unterminatedQuote)
{
    Utf8 result;
    result.reserve(line.size());

    bool inSingleQuote = false;
    bool inDoubleQuote = false;
    for (const char c : line)
    {
        if (c == '\'' && !inDoubleQuote)
        {
            inSingleQuote = !inSingleQuote;
            result += c;
            continue;
        }

        if (c == '"' && !inSingleQuote)
        {
            inDoubleQuote = !inDoubleQuote;
            result += c;
            continue;
        }

        if (c == '#' && !inSingleQuote && !inDoubleQuote)
            break;

        result += c;
    }

    unterminatedQuote = inSingleQuote || inDoubleQuote;
    return result;
}

size_t StructConfigReader::findAssignment(const std::string_view line)
{
    bool inSingleQuote = false;
    bool inDoubleQuote = false;

    for (size_t i = 0; i < line.size(); i++)
    {
        const char c = line[i];
        if (c == '\'' && !inDoubleQuote)
        {
            inSingleQuote = !inSingleQuote;
            continue;
        }

        if (c == '"' && !inSingleQuote)
        {
            inDoubleQuote = !inDoubleQuote;
            continue;
        }

        if (c == '=' && !inSingleQuote && !inDoubleQuote)
            return i;
    }

    return std::string_view::npos;
}

bool StructConfigReader::reportUnknownKey(TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& key) const
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_unknown_key);
    diag.addArgument(Diagnostic::ARG_ARG, key);
    diag.addArgument(Diagnostic::ARG_PATH, formatConfigLocation(ctx, sourcePath, lineNo));
    diag.addDidYouMeanNote(schema_->suggest(key.view()));
    diag.report(ctx);
    return false;
}

bool StructConfigReader::reportInvalidEnum(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_invalid_enum);
    diag.addArgument(Diagnostic::ARG_ARG, entry.name);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.addArgument(Diagnostic::ARG_PATH, formatConfigLocation(ctx, sourcePath, lineNo));
    diag.addArgument(Diagnostic::ARG_VALUES, Utf8Helper::join(entry.choices, "|"));
    diag.addDidYouMeanNote(Utf8Helper::bestMatch(value.view(), entry.choices));
    diag.report(ctx);
    return false;
}

bool StructConfigReader::applyEntry(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, const uint32_t lineNo, const std::string_view valueText, const fs::path& baseDir)
{
    Utf8 value{Utf8Helper::trim(valueText)};
    if (value.size() >= 2)
    {
        const char first = value.front();
        const char last  = value.back();
        if ((first == '\'' || first == '"') && last == first)
            value = value.substr(1, value.size() - 2);
    }

    if (auto* target = std::get_if<bool*>(&entry.target))
    {
        bool parsedValue = false;
        if (!parseBool(value.view(), parsedValue))
            return reportInvalidScalarValue(ctx, DiagnosticId::cmd_err_config_invalid_bool, entry, sourcePath, lineNo, value);
        **target = parsedValue;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<int*>(&entry.target))
    {
        int parsedValue = 0;
        if (!parseIntegerValue(value, parsedValue))
            return reportInvalidScalarValue(ctx, DiagnosticId::cmd_err_config_invalid_int, entry, sourcePath, lineNo, value);
        **target = parsedValue;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<uint32_t*>(&entry.target))
    {
        uint32_t parsedValue = 0;
        if (!parseIntegerValue(value, parsedValue))
            return reportInvalidScalarValue(ctx, DiagnosticId::cmd_err_config_invalid_int, entry, sourcePath, lineNo, value);
        **target = parsedValue;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<Utf8*>(&entry.target))
    {
        if (!entry.choices.empty())
        {
            for (const Utf8& choice : entry.choices)
            {
                if (choice == value)
                {
                    **target = value;
                    entry.afterSet.invoke();
                    return true;
                }
            }

            return reportInvalidEnum(ctx, entry, sourcePath, lineNo, value);
        }

        **target = value;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<fs::path*>(&entry.target))
    {
        **target = resolveConfigPathValue(value, baseDir);
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<std::vector<Utf8>*>(&entry.target))
    {
        (*target)->push_back(value);
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<std::set<Utf8>*>(&entry.target))
    {
        (*target)->insert(value);
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<std::set<fs::path>*>(&entry.target))
    {
        (*target)->insert(resolveConfigPathValue(value, baseDir));
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<std::optional<bool>*>(&entry.target))
    {
        Utf8 normalized = value;
        normalized.make_lower();
        if (normalized == "preserve")
        {
            **target = std::nullopt;
            entry.afterSet.invoke();
            return true;
        }

        bool parsedValue = false;
        if (!parseBool(value.view(), parsedValue))
            return reportInvalidScalarValue(ctx, DiagnosticId::cmd_err_config_invalid_bool, entry, sourcePath, lineNo, value);
        **target = parsedValue;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<StructConfigEnumIntTarget>(&entry.target))
    {
        for (size_t i = 0; i < entry.choices.size(); i++)
        {
            if (entry.choices[i] == value)
            {
                target->setter(target->target, entry.choiceIntValues[i]);
                entry.afterSet.invoke();
                return true;
            }
        }

        return reportInvalidEnum(ctx, entry, sourcePath, lineNo, value);
    }

    SWC_UNREACHABLE();
}

Result StructConfigReader::readFile(TaskContext& ctx, const fs::path& path) const
{
    const fs::path normalizedPath = FileSystem::normalizePath(path);

    std::string             content;
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::readTextFile(normalizedPath, content, ioError) != Result::Continue)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_read_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, normalizedPath, FileSystem::describeIoFailure(ioError));
        diag.report(ctx);
        return Result::Error;
    }

    if (content.size() >= 3 &&
        static_cast<unsigned char>(content[0]) == 0xEF &&
        static_cast<unsigned char>(content[1]) == 0xBB &&
        static_cast<unsigned char>(content[2]) == 0xBF)
    {
        content.erase(0, 3);
    }

    std::istringstream stream(content);
    std::string        rawLine;
    uint32_t           lineNo  = 0;
    const fs::path     baseDir = normalizedPath.parent_path();

    while (std::getline(stream, rawLine))
    {
        lineNo++;
        if (!rawLine.empty() && rawLine.back() == '\r')
            rawLine.pop_back();

        bool unterminatedQuote = false;
        Utf8 line              = stripInlineComment(rawLine, unterminatedQuote);
        if (unterminatedQuote)
            return reportInvalidConfigEntry(ctx, normalizedPath, lineNo, "unterminated quoted value");

        line.trim();
        if (line.empty())
            continue;

        const size_t assignPos = findAssignment(line.view());
        if (assignPos == std::string_view::npos)
            return reportInvalidConfigEntry(ctx, normalizedPath, lineNo, "expected 'key = value'");

        auto key = Utf8(Utf8Helper::trim(line.view().substr(0, assignPos)));
        if (key.empty())
            return reportInvalidConfigEntry(ctx, normalizedPath, lineNo, "missing config key");

        const StructConfigEntry* entry = schema_->find(key.view());
        if (!entry)
        {
            reportUnknownKey(ctx, normalizedPath, lineNo, key);
            return Result::Error;
        }

        const std::string_view value = Utf8Helper::trim(line.view().substr(assignPos + 1));
        if (!applyEntry(ctx, *entry, normalizedPath, lineNo, value, baseDir))
            return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
