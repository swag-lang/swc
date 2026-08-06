#include "pch.h"
#include "Support/Report/WarningPolicy.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void applyLevel(WarningLevel& level, const std::optional<WarningLevel>& decision)
    {
        if (decision.has_value())
            level = decision.value();
    }
}

void WarningPolicy::reset()
{
    levels_.clear();
    blanketLevel_.reset();
}

void WarningPolicy::setLevel(DiagnosticId id, WarningLevel level)
{
    SWC_ASSERT(isWarningId(id));

    for (Entry& entry : levels_)
    {
        if (entry.id == id)
        {
            entry.level = level;
            return;
        }
    }

    levels_.push_back({.id = id, .level = level});
}

std::optional<WarningLevel> WarningPolicy::levelOf(DiagnosticId id) const
{
    for (const Entry& entry : levels_)
    {
        if (entry.id == id)
            return entry.level;
    }

    return std::nullopt;
}

std::optional<Utf8> WarningPolicy::addList(std::string_view names, WarningLevel level)
{
    size_t pos = 0;
    while (pos < names.size())
    {
        size_t end = names.find_first_of("|,", pos);
        if (end == std::string_view::npos)
            end = names.size();

        const std::string_view name = Utf8Helper::trim(names.substr(pos, end - pos));
        pos                         = end + 1;
        if (name.empty())
            continue;

        if (name == ALL)
        {
            setBlanketLevel(level);
            continue;
        }

        const DiagnosticId id = findId(name);
        if (id == DiagnosticId::None)
            return Utf8{name};

        setLevel(id, level);
    }

    return std::nullopt;
}

bool WarningPolicy::isWarningId(DiagnosticId id)
{
    if (id == DiagnosticId::None || id == DiagnosticId::Count)
        return false;
    return Diagnostic::diagIdSeverity(id) == DiagnosticSeverity::Warning;
}

DiagnosticId WarningPolicy::findId(std::string_view name)
{
    for (size_t index = 1; index < static_cast<size_t>(DiagnosticId::Count); index++)
    {
        const auto id = static_cast<DiagnosticId>(index);
        if (isWarningId(id) && Diagnostic::diagIdName(id) == name)
            return id;
    }

    return DiagnosticId::None;
}

std::vector<Utf8> WarningPolicy::allIdNames()
{
    std::vector<Utf8> result;
    result.emplace_back(ALL);

    for (size_t index = 1; index < static_cast<size_t>(DiagnosticId::Count); index++)
    {
        const auto id = static_cast<DiagnosticId>(index);
        if (isWarningId(id))
            result.emplace_back(Diagnostic::diagIdName(id));
    }

    return result;
}

WarningLevel resolveWarningLevel(const WarningLevelQuery& query)
{
    WarningLevel level = WarningLevel::Warning;

    if (query.cmdLine)
        applyLevel(level, query.cmdLine->blanketLevel());
    if (query.buildCfg)
        applyLevel(level, query.buildCfg->blanketLevel());
    applyLevel(level, query.sourceBlanketLevel);

    if (query.cmdLine)
        applyLevel(level, query.cmdLine->levelOf(query.id));
    if (query.buildCfg)
        applyLevel(level, query.buildCfg->levelOf(query.id));
    applyLevel(level, query.sourceLevel);

    return level;
}

SWC_END_NAMESPACE();
