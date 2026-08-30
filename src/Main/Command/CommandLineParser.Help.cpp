#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Support/Report/Assert.h"
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

    Utf8 pathToUtf8String(const fs::path& path)
    {
        return Utf8{path.string()};
    }

    bool commandInfoNameLess(const CommandInfo& lhs, const CommandInfo& rhs)
    {
        return Utf8(lhs.name) < Utf8(rhs.name);
    }

    bool helpOptionEntryLess(const HelpOptionEntry& lhs, const HelpOptionEntry& rhs)
    {
        const int leftOrder  = static_cast<int>(lhs.group);
        const int rightOrder = static_cast<int>(rhs.group);
        if (leftOrder != rightOrder)
            return leftOrder < rightOrder;
        if (lhs.displayName != rhs.displayName)
            return lhs.displayName < rhs.displayName;
        return lhs.arg->description < rhs.arg->description;
    }

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
            const Utf8 value = Utf8Helper::join(**t, ", ", pathToUtf8String);
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
    addInfoEntry(entries, "Language", "A systems language that runs at compile time");
    if (!command.empty())
        addInfoEntry(entries, "Command", command, LogColor::BrightYellow);

    Logger::FieldGroupStyle headerStyle = nextHelpGroupStyle(hasPrintedGroup, 16);
    headerStyle.blankLineBefore         = false;
    Logger::printFieldGroup(ctx, "swc", entries, headerStyle);

    entries.clear();
    if (command.empty())
    {
        addInfoEntry(entries, "swc", "<command> [options]", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc", "<script.swgs> [options]", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc help", "<command>", LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Usage", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        addInfoEntry(entries, "Create", "swc new script hello", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Run", "swc hello.swgs", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Source", R"(#main { Swag.print("Hello, world!\n") })", LogColor::White, 0, LogColor::Dim);
        Logger::printFieldGroup(ctx, "First Script", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        addInfoEntry(entries, "Create", "swc new module hello", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Run", "swc run --workspace hello --workspace-module hello", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Add a module", "swc new module tools --workspace hello", LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "First Workspace", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        addInfoEntry(entries, "Getting started", "https://www.swag-lang.org/getting-started.html", LogColor::BrightBlue);
        addInfoEntry(entries, "Language reference", "https://www.swag-lang.org/language.html", LogColor::BrightBlue);
        addInfoEntry(entries, "Examples", "https://github.com/swag-lang/swc/tree/master/bin/examples", LogColor::BrightBlue);
        addInfoEntry(entries, "Native setup", "Install the MSVC x64 build tools and the Windows SDK");
        addInfoEntry(entries, "Command help", "swc help <command>", LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Learn", entries, nextHelpGroupStyle(hasPrintedGroup, 22));

        entries.clear();
        std::vector commands(std::begin(COMMANDS), std::end(COMMANDS));
        std::ranges::sort(commands, commandInfoNameLess);
        for (const CommandInfo& cmd : commands)
            addInfoEntry(entries, cmd.name, cmd.description, LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Commands", entries, nextHelpGroupStyle(hasPrintedGroup, 12));
        return;
    }

    if (command == "new")
    {
        addInfoEntry(entries, "swc new script", "[path]", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc new module", "<name> [--workspace <path>]", LogColor::White, 0, helpArgumentLabelColor());
    }
    else
    {
        addInfoEntry(entries, std::format("swc {}", command), "[options]", LogColor::White, 0, helpArgumentLabelColor());
    }
    Logger::printFieldGroup(ctx, "Usage", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

    if (command == "new")
    {
        entries.clear();
        addInfoEntry(entries, "script", "Create a runnable Hello World script; default path: hello.swgs", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "script path", "Add .swgs when the path has no extension", LogColor::White, 0, LogColor::Dim);
        addInfoEntry(entries, "module", "Create an executable module in a new workspace named after the module", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--workspace", "Create or extend the workspace at this path", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Existing paths", "Stop without overwriting files or modules", LogColor::White, 0, LogColor::Dim);
        Logger::printFieldGroup(ctx, "Creates", entries, nextHelpGroupStyle(hasPrintedGroup, 20));

        entries.clear();
        addInfoEntry(entries, "Script", "swc new script hello", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "New workspace", "swc new module hello", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Existing workspace", "swc new module tools --workspace hello", LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Examples", entries, nextHelpGroupStyle(hasPrintedGroup, 20));
        return;
    }

    if (command == "clean")
    {
        entries.clear();
        addInfoEntry(entries, "--workspace", "Remove the .output, .tmp, and .dep directories of that workspace", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--workspace-module", "Restrict the removal to one module, keeping the .dep directory the workspace shares", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--module", "Remove the .output directory under that module root, and --out-dir and --work-dir when they are set", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--cache", "Remove every dependency copy a script filled outside a workspace", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--cache-days", "Keep the copies a run has used within that many days", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--dry-run", "Report what each target holds and remove nothing", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Absent paths", "Count as already clean", LogColor::White, 0, LogColor::Dim);
        Logger::printFieldGroup(ctx, "Removes", entries, nextHelpGroupStyle(hasPrintedGroup, 20));

        entries.clear();
        addInfoEntry(entries, "Workspace", "swc clean --workspace bin/std", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "One module", "swc clean --workspace bin/std --workspace-module core", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Script copies", "swc clean --cache", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Stale copies", "swc clean --cache --cache-days 7", LogColor::White, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Preview", "swc clean --workspace bin/std --dry-run", LogColor::White, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Examples", entries, nextHelpGroupStyle(hasPrintedGroup, 20));
        return;
    }

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
        entry.displayName = Utf8(arg.longForm);
        if (!arg.shortForm.empty())
        {
            entry.displayName += ", ";
            entry.displayName.append(arg.shortForm);
        }

        entry.group = arg.group;
        helpEntries.push_back(std::move(entry));
    }

    std::ranges::sort(helpEntries, helpOptionEntryLess);

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
