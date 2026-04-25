#include "pch.h"
#include "Main/StructConfig.h"
#include "Main/FileSystem.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

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

StructConfigEntry& StructConfigSchema::add(const char* name, bool* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, int* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, uint32_t* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, Utf8* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, fs::path* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, std::vector<Utf8>* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, std::set<Utf8>* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, std::set<fs::path>* target, const char* description, const StructConfigAssignHook hook)
{
    return addImpl(name, description, target, hook);
}

StructConfigEntry& StructConfigSchema::add(const char* name, std::optional<bool>* target, const char* description, const StructConfigAssignHook hook)
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

    return StructConfigReader::bestMatch(query, candidates);
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

bool StructConfigReader::parseInt(const std::string_view value, int& result)
{
    const char* first = value.data();
    const char* last  = first + value.size();
    if (first == last)
        return false;

    const auto [ptr, ec] = std::from_chars(first, last, result);
    return ec == std::errc{} && ptr == last;
}

bool StructConfigReader::parseUInt(const std::string_view value, uint32_t& result)
{
    const char* first = value.data();
    const char* last  = first + value.size();
    if (first == last)
        return false;

    const auto [ptr, ec] = std::from_chars(first, last, result);
    return ec == std::errc{} && ptr == last;
}

std::optional<Utf8> StructConfigReader::bestMatch(const std::string_view query, const std::vector<Utf8>& candidates)
{
    if (candidates.empty() || query.length() < 3)
        return std::nullopt;

    const size_t maxDist = std::max<size_t>(1, std::min<size_t>(3, query.length() / 3));

    size_t      bestDist = std::numeric_limits<size_t>::max();
    const Utf8* best     = nullptr;
    for (const Utf8& candidate : candidates)
    {
        const size_t distance = Utf8Helper::levenshtein(query, candidate);
        if (distance < bestDist)
        {
            bestDist = distance;
            best     = &candidate;
        }
    }

    if (!best || bestDist > maxDist)
        return std::nullopt;

    return *best;
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

Utf8 StructConfigReader::unquoteValue(const std::string_view value)
{
    if (value.size() >= 2)
    {
        const char first = value.front();
        const char last  = value.back();
        if ((first == '\'' || first == '"') && last == first)
            return Utf8{value.substr(1, value.size() - 2)};
    }

    return Utf8{value};
}

void StructConfigReader::attachSuggestion(Diagnostic& diag, std::optional<Utf8> suggestion)
{
    if (!suggestion.has_value())
        return;

    DiagnosticElement& note = diag.addElement(DiagnosticId::cmd_note_did_you_mean);
    note.setSeverity(DiagnosticSeverity::Note);
    note.addArgument(Diagnostic::ARG_VALUE, suggestion.value());
}

bool StructConfigReader::reportUnknownKey(TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& key) const
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_unknown_key);
    diag.addArgument(Diagnostic::ARG_ARG, key);
    diag.addArgument(Diagnostic::ARG_PATH, !lineNo ? FileSystem::formatDiagnosticPath(&ctx, sourcePath) : FileSystem::formatFileLocation(&ctx, sourcePath, lineNo));
    attachSuggestion(diag, schema_->suggest(key.view()));
    diag.report(ctx);
    return false;
}

bool StructConfigReader::reportInvalidEntry(TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& because)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_invalid_entry);
    diag.addArgument(Diagnostic::ARG_PATH, !lineNo ? FileSystem::formatDiagnosticPath(&ctx, sourcePath) : FileSystem::formatFileLocation(&ctx, sourcePath, lineNo));
    diag.addArgument(Diagnostic::ARG_BECAUSE, because);
    diag.report(ctx);
    return false;
}

bool StructConfigReader::reportInvalidBool(TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& key, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_invalid_bool);
    diag.addArgument(Diagnostic::ARG_ARG, key);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.addArgument(Diagnostic::ARG_PATH, !lineNo ? FileSystem::formatDiagnosticPath(&ctx, sourcePath) : FileSystem::formatFileLocation(&ctx, sourcePath, lineNo));
    diag.report(ctx);
    return false;
}

bool StructConfigReader::reportInvalidInt(TaskContext& ctx, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& key, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_invalid_int);
    diag.addArgument(Diagnostic::ARG_ARG, key);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.addArgument(Diagnostic::ARG_PATH, !lineNo ? FileSystem::formatDiagnosticPath(&ctx, sourcePath) : FileSystem::formatFileLocation(&ctx, sourcePath, lineNo));
    diag.report(ctx);
    return false;
}

bool StructConfigReader::reportInvalidEnum(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, const uint32_t lineNo, const Utf8& value)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_config_invalid_enum);
    diag.addArgument(Diagnostic::ARG_ARG, entry.name);
    diag.addArgument(Diagnostic::ARG_VALUE, value);
    diag.addArgument(Diagnostic::ARG_PATH, !lineNo ? FileSystem::formatDiagnosticPath(&ctx, sourcePath) : FileSystem::formatFileLocation(&ctx, sourcePath, lineNo));

    Utf8 choices;
    for (const Utf8& choice : entry.choices)
    {
        if (!choices.empty())
            choices += "|";
        choices += choice;
    }

    diag.addArgument(Diagnostic::ARG_VALUES, choices);
    attachSuggestion(diag, bestMatch(value.view(), entry.choices));
    diag.report(ctx);
    return false;
}

bool StructConfigReader::applyEntry(TaskContext& ctx, const StructConfigEntry& entry, const fs::path& sourcePath, const uint32_t lineNo, const std::string_view valueText, const fs::path& baseDir)
{
    const Utf8 value = unquoteValue(Utf8Helper::trim(valueText));

    if (auto* target = std::get_if<bool*>(&entry.target))
    {
        bool parsedValue = false;
        if (!parseBool(value.view(), parsedValue))
            return reportInvalidBool(ctx, sourcePath, lineNo, entry.name, value);
        **target = parsedValue;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<int*>(&entry.target))
    {
        int parsedValue = 0;
        if (!parseInt(value.view(), parsedValue))
            return reportInvalidInt(ctx, sourcePath, lineNo, entry.name, value);
        **target = parsedValue;
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<uint32_t*>(&entry.target))
    {
        uint32_t parsedValue = 0;
        if (!parseUInt(value.view(), parsedValue))
            return reportInvalidInt(ctx, sourcePath, lineNo, entry.name, value);
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
        fs::path path = value.c_str();
        if (!value.empty() && path.is_relative())
            path = (baseDir / path).lexically_normal();
        **target = std::move(path);
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
        fs::path path = value.c_str();
        if (!value.empty() && path.is_relative())
            path = (baseDir / path).lexically_normal();
        (*target)->insert(std::move(path));
        entry.afterSet.invoke();
        return true;
    }

    if (auto* target = std::get_if<std::optional<bool>*>(&entry.target))
    {
        bool parsedValue = false;
        if (!parseBool(value.view(), parsedValue))
            return reportInvalidBool(ctx, sourcePath, lineNo, entry.name, value);
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
        {
            reportInvalidEntry(ctx, normalizedPath, lineNo, "unterminated quoted value");
            return Result::Error;
        }

        line.trim();
        if (line.empty())
            continue;

        const size_t assignPos = findAssignment(line.view());
        if (assignPos == std::string_view::npos)
        {
            reportInvalidEntry(ctx, normalizedPath, lineNo, "expected 'key = value'");
            return Result::Error;
        }

        auto key = Utf8(Utf8Helper::trim(line.view().substr(0, assignPos)));
        if (key.empty())
        {
            reportInvalidEntry(ctx, normalizedPath, lineNo, "missing config key");
            return Result::Error;
        }

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
