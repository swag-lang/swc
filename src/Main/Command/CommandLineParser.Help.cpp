#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::addInfoEntry;

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

    CommandPrint::printCompilerHeader(ctx);
    if (command.empty())
    {
        addInfoEntry(entries, "", "Compile native programs and run Swag scripts");
        addInfoEntry(entries, "", "Output is one plain ASCII record per line, written for the agent that launches swc");
        Logger::printFieldGroup(ctx, "", entries);
        entries.clear();
        addInfoEntry(entries, "swc", "<command> [options]");
        addInfoEntry(entries, "swc", "[compiler options] <script.swgs> [script arguments]");
        addInfoEntry(entries, "swc help", "<command>");
        Logger::printFieldGroup(ctx, "Usage", entries);

        entries.clear();
        addInfoEntry(entries, "Create", "swc new script hello");
        addInfoEntry(entries, "Run", "swc hello.swgs");
        Logger::printFieldGroup(ctx, "First script", entries);

        entries.clear();
        addInfoEntry(entries, "Create", "swc new module hello");
        addInfoEntry(entries, "Run", "swc run --workspace hello --workspace-module hello");
        Logger::printFieldGroup(ctx, "First workspace", entries);

        entries.clear();
        for (const CommandInfo& cmd : COMMANDS)
            addInfoEntry(entries, cmd.name, cmd.description);
        Logger::printFieldGroup(ctx, "Commands", entries);

        entries.clear();
        addInfoEntry(entries, "Command options", "swc help <command>");
        addInfoEntry(entries, "Paths and setup", "swc info");
        addInfoEntry(entries, "Native setup", "Install the MSVC x64 build tools and the Windows SDK");
        addInfoEntry(entries, "Getting started", "https://www.swag-lang.org/getting-started.html");
        addInfoEntry(entries, "Reference", "https://www.swag-lang.org/language.html");
        addInfoEntry(entries, "Examples", "https://github.com/swag-lang/swc/tree/master/bin/examples");
        Logger::printFieldGroup(ctx, "More help", entries);
        return;
    }

    for (const CommandInfo& cmd : COMMANDS)
    {
        if (command == cmd.name)
            addInfoEntry(entries, command, cmd.description);
    }
    Logger::printFieldGroup(ctx, "Command", entries);
    entries.clear();
    if (command == "new")
    {
        addInfoEntry(entries, "swc new script", "[path]");
        addInfoEntry(entries, "swc new module", "<name> [--workspace <path>]");
    }
    else
    {
        addInfoEntry(entries, std::format("swc {}", command), "[options]");
    }
    Logger::printFieldGroup(ctx, "Usage", entries);

    if (command == "info")
    {
        entries.clear();
        addInfoEntry(entries, "Installation", "Show the executable, resource folders, standard modules, and SWAG_PATH");
        addInfoEntry(entries, "Caches", "Show absolute paths for dependency copies, machine code, and legacy script caches");
        addInfoEntry(entries, "Native toolchain", "Show the MSVC and Windows SDK libraries selected by the compiler");
        addInfoEntry(entries, "--workspace <path>", "Also show this workspace's output, intermediate, and dependency folders");
        addInfoEntry(entries, "--workspace-module <name>", "Show output and intermediate folders for one workspace module");
        addInfoEntry(entries, "--module <path>", "Also show this module's output and intermediate folders");
        addInfoEntry(entries, "Inspection", "Read the installation without compiling sources or creating folders");
        Logger::printFieldGroup(ctx, "Reports", entries);
        return;
    }

    if (command == "new")
    {
        entries.clear();
        addInfoEntry(entries, "script", "Create a runnable Hello World script; default path: hello.swgs");
        addInfoEntry(entries, "script path", "Add .swgs when the path has no extension");
        addInfoEntry(entries, "module", "Create an executable module in a new workspace named after the module");
        addInfoEntry(entries, "--workspace", "Create or extend the workspace at this path");
        addInfoEntry(entries, "Existing paths", "Stop without overwriting files or modules");
        Logger::printFieldGroup(ctx, "Creates", entries);

        entries.clear();
        addInfoEntry(entries, "Script", "swc new script hello");
        addInfoEntry(entries, "New workspace", "swc new module hello");
        addInfoEntry(entries, "Existing workspace", "swc new module tools --workspace hello");
        Logger::printFieldGroup(ctx, "Examples", entries);
        return;
    }

    if (command == "clean")
    {
        entries.clear();
        addInfoEntry(entries, "--workspace", "Remove the .output, .tmp, and .dep directories of that workspace");
        addInfoEntry(entries, "--workspace-module", "Restrict the removal to one module, keeping the .dep directory the workspace shares");
        addInfoEntry(entries, "--module", "Remove the .output and .tmp directories under that module root, and --out-dir and --work-dir when they are set");
        addInfoEntry(entries, "--cache", "Remove dependency copies and binary compiler caches kept outside workspaces");
        addInfoEntry(entries, "--cache-days", "Keep the copies a run has used within that many days");
        addInfoEntry(entries, "--dry-run", "Report what each target holds and remove nothing");
        addInfoEntry(entries, "Absent paths", "Count as already clean");
        Logger::printFieldGroup(ctx, "Removes", entries);

        entries.clear();
        addInfoEntry(entries, "Workspace", "swc clean --workspace bin/std");
        addInfoEntry(entries, "One module", "swc clean --workspace bin/std --workspace-module core");
        addInfoEntry(entries, "Script copies", "swc clean --cache");
        addInfoEntry(entries, "Stale copies", "swc clean --cache --cache-days 7");
        addInfoEntry(entries, "Preview", "swc clean --workspace bin/std --dry-run");
        Logger::printFieldGroup(ctx, "Examples", entries);
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
                Logger::printFieldGroup(ctx, helpOptionGroupName(currentGroup), groupEntries);
                groupEntries.clear();
            }

            currentGroup = entry.group;
            firstGroup   = false;
        }

        addInfoEntry(groupEntries, entry.displayName, entry.arg->description);
        if (entry.arg->isEnum())
        {
            addInfoEntry(groupEntries, "choices", Utf8Helper::join(entry.arg->choices, ", "), 1);
        }

        // An option without a default value says so by having no 'default' line.
        const Utf8 defaultValue = defaultValueToString(*entry.arg);
        if (defaultValue != "(none)")
            addInfoEntry(groupEntries, "default", defaultValue, 1);
    }

    if (!groupEntries.empty())
        Logger::printFieldGroup(ctx, helpOptionGroupName(currentGroup), groupEntries);

    command_ = oldCommand;
}

SWC_END_NAMESPACE();
