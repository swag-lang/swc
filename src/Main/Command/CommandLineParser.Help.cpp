#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::addInfoEntry;
    using CommandPrint::helpArgumentLabelColor;
    using CommandPrint::nextHelpGroupStyle;

    struct HelpOptionEntry
    {
        const ArgInfo*  arg = nullptr;
        Utf8            displayName;
        HelpOptionGroup group = HelpOptionGroup::Other;
    };

    const char* helpOptionGroupName(const HelpOptionGroup group)
    {
        switch (group)
        {
            case HelpOptionGroup::Input:
                return "Input";
            case HelpOptionGroup::Target:
                return "Target";
            case HelpOptionGroup::Compiler:
                return "Compiler";
            case HelpOptionGroup::Diagnostics:
                return "Diagnostics";
            case HelpOptionGroup::Logging:
                return "Logging";
            case HelpOptionGroup::Testing:
                return "Testing";
            case HelpOptionGroup::Development:
                return "Development";
            case HelpOptionGroup::Other:
                return "Other";
        }

        SWC_UNREACHABLE();
    }

    Utf8 defaultValueToString(const ArgInfo& arg)
    {
        if (auto* t = std::get_if<bool*>(&arg.target))
            return **t ? "true" : "false";
        if (auto* t = std::get_if<int*>(&arg.target))
            return std::to_string(**t);
        if (auto* t = std::get_if<uint32_t*>(&arg.target))
            return std::to_string(**t);
        if (auto* t = std::get_if<Utf8*>(&arg.target))
            return (*t)->empty() ? Utf8("(none)") : **t;
        if (auto* t = std::get_if<fs::path*>(&arg.target))
        {
            Utf8 value = (*t)->empty() ? Utf8{} : Utf8((*t)->string());
            return value.empty() ? Utf8("(none)") : value;
        }
        if (auto* t = std::get_if<std::vector<Utf8>*>(&arg.target))
        {
            const Utf8 value = Utf8Helper::join(**t, ", ");
            return value.empty() ? Utf8("(none)") : value;
        }
        if (auto* t = std::get_if<std::set<Utf8>*>(&arg.target))
        {
            const Utf8 value = Utf8Helper::join(**t, ", ");
            return value.empty() ? Utf8("(none)") : value;
        }
        if (auto* t = std::get_if<std::set<fs::path>*>(&arg.target))
        {
            const Utf8 value = Utf8Helper::join(**t, ", ", [](const fs::path& entry) { return Utf8(entry.string()); });
            return value.empty() ? Utf8("(none)") : value;
        }
        if (auto* t = std::get_if<std::optional<bool>*>(&arg.target))
        {
            if (!(*t)->has_value())
                return "(auto)";
            return (*t)->value() ? "true" : "false";
        }
        if (auto* t = std::get_if<EnumIntTarget>(&arg.target))
        {
            const int value = t->getter(t->target);
            for (size_t i = 0; i < arg.choiceIntValues.size(); i++)
            {
                if (arg.choiceIntValues[i] == value)
                    return arg.choices[i];
            }

            return std::to_string(value);
        }

        SWC_UNREACHABLE();
    }

}

void CommandLineParser::printHelp(const TaskContext& ctx, const Utf8& command)
{
    const Logger::ScopedLock        loggerLock(ctx.global().logger());
    std::vector<Logger::FieldEntry> entries;
    bool                            hasPrintedGroup = false;

    addInfoEntry(entries, "Version", std::format("swag compiler {}.{}.{}", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM), LogColor::BrightGreen);
    if (!command.empty())
        addInfoEntry(entries, "Command", command, LogColor::BrightYellow);

    Logger::FieldGroupStyle headerStyle = nextHelpGroupStyle(hasPrintedGroup, 16);
    headerStyle.blankLineBefore         = false;
    Logger::printFieldGroup(ctx, "swc", entries, headerStyle);

    entries.clear();
    if (command.empty())
    {
        addInfoEntry(entries, "swc", "<command> [options]", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc help", "<command>", LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Usage", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        std::vector commands(std::begin(COMMANDS), std::end(COMMANDS));
        std::ranges::sort(commands, [](const CommandInfo& lhs, const CommandInfo& rhs) { return Utf8(lhs.name) < Utf8(rhs.name); });
        for (const CommandInfo& cmd : commands)
            addInfoEntry(entries, cmd.name, cmd.description, LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Commands", entries, nextHelpGroupStyle(hasPrintedGroup, 12));
        return;
    }

    addInfoEntry(entries, std::format("swc {}", command), "[options]", LogColor::White, 0, helpArgumentLabelColor());
    Logger::printFieldGroup(ctx, "Usage", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

    const Utf8 oldCommand = command_;
    command_              = command;

    std::vector<HelpOptionEntry> helpEntries;
    helpEntries.reserve(args_.size());
    for (const ArgInfo& arg : args_)
    {
        if (!commandMatches(arg.commands))
            continue;

        HelpOptionEntry entry;
        entry.arg         = &arg;
        entry.displayName = arg.longForm;
        if (!arg.shortForm.empty())
        {
            entry.displayName += ", ";
            entry.displayName += arg.shortForm;
        }

        entry.group = arg.group;
        helpEntries.push_back(std::move(entry));
    }

    std::ranges::sort(helpEntries, [](const HelpOptionEntry& lhs, const HelpOptionEntry& rhs) {
        const int leftOrder  = static_cast<int>(lhs.group);
        const int rightOrder = static_cast<int>(rhs.group);
        if (leftOrder != rightOrder)
            return leftOrder < rightOrder;

        if (lhs.displayName != rhs.displayName)
            return lhs.displayName < rhs.displayName;

        return lhs.arg->description < rhs.arg->description;
    });

    auto                            currentGroup = HelpOptionGroup::Other;
    bool                            firstGroup   = true;
    std::vector<Logger::FieldEntry> groupEntries;
    for (const HelpOptionEntry& entry : helpEntries)
    {
        if (firstGroup || currentGroup != entry.group)
        {
            if (!groupEntries.empty())
            {
                Logger::printFieldGroup(ctx, helpOptionGroupName(currentGroup), groupEntries, nextHelpGroupStyle(hasPrintedGroup, 34));
                groupEntries.clear();
            }

            currentGroup = entry.group;
            firstGroup   = false;
        }

        addInfoEntry(groupEntries, entry.displayName, entry.arg->description, LogColor::White, 0, helpArgumentLabelColor());
        if (entry.arg->isEnum())
        {
            addInfoEntry(groupEntries, "choices", Utf8Helper::join(entry.arg->choices, ", "), LogColor::Yellow, 1, LogColor::Dim);
        }
        addInfoEntry(groupEntries, "default", defaultValueToString(*entry.arg), LogColor::BrightGreen, 1, LogColor::Dim);
    }

    if (!groupEntries.empty())
        Logger::printFieldGroup(ctx, helpOptionGroupName(currentGroup), groupEntries, nextHelpGroupStyle(hasPrintedGroup, 34));

    command_ = oldCommand;
}

SWC_END_NAMESPACE();
