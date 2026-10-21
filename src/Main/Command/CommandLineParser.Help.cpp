#include "pch.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
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
    bool                            hasPrintedGroup = true;

    CommandPrint::printCompilerHeader(ctx);
    if (command.empty())
    {
        Logger::FieldGroupStyle introStyle = CommandPrint::helpGroupStyle(false);
        introStyle.lineIndent              = 0;
        introStyle.minLabelWidth           = 0;
        introStyle.maxLabelWidth           = 0;
        addInfoEntry(entries, "", "Compile native programs and run Swag scripts", LogColor::Reset);
        addInfoEntry(entries, "", "A systems language with compile-time execution", LogColor::Reset);
        Logger::printFieldGroup(ctx, "", entries, introStyle);
        entries.clear();
        addInfoEntry(entries, "swc", "<command> [options]", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc", "[compiler options] <script.swgs> [script arguments]", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc help", "<command>", LogColor::Reset, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Usage", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        addInfoEntry(entries, "Create", "swc new script hello", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Run", "swc hello.swgs", LogColor::Reset, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "First script", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        addInfoEntry(entries, "Create", "swc new module hello", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Run", "swc run --workspace hello --workspace-module hello", LogColor::Reset, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "First workspace", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

        entries.clear();
        for (const CommandInfo& cmd : COMMANDS)
            addInfoEntry(entries, cmd.name, cmd.description, LogColor::Reset, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Commands", entries, nextHelpGroupStyle(hasPrintedGroup, 12));

        entries.clear();
        addInfoEntry(entries, "Command options", "swc help <command>", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Paths and setup", "swc info", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Native setup", "Install the MSVC x64 build tools and the Windows SDK");
        addInfoEntry(entries, "Getting started", "https://www.swag-lang.org/getting-started.html", LogColor::BrandArc);
        addInfoEntry(entries, "Reference", "https://www.swag-lang.org/language.html", LogColor::BrandArc);
        addInfoEntry(entries, "Examples", "https://github.com/swag-lang/swc/tree/master/bin/examples", LogColor::BrandArc);
        Logger::printFieldGroup(ctx, "More help", entries, nextHelpGroupStyle(hasPrintedGroup, 22));
        return;
    }

    for (const CommandInfo& cmd : COMMANDS)
    {
        if (command == cmd.name)
            addInfoEntry(entries, command, cmd.description, LogColor::Reset, 0, helpArgumentLabelColor());
    }
    Logger::printFieldGroup(ctx, "Command", entries, nextHelpGroupStyle(hasPrintedGroup, 18));
    entries.clear();
    if (command == "new")
    {
        addInfoEntry(entries, "swc new script", "[path]", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "swc new module", "<name> [--workspace <path>]", LogColor::Reset, 0, helpArgumentLabelColor());
    }
    else
    {
        addInfoEntry(entries, std::format("swc {}", command), "[options]", LogColor::Reset, 0, helpArgumentLabelColor());
    }
    Logger::printFieldGroup(ctx, "Usage", entries, nextHelpGroupStyle(hasPrintedGroup, 18));

    if (command == "info")
    {
        entries.clear();
        addInfoEntry(entries, "Installation", "Show the executable, resource folders, standard modules, and SWAG_PATH");
        addInfoEntry(entries, "Caches", "Show absolute paths for dependency copies, machine code, and legacy script caches");
        addInfoEntry(entries, "Native toolchain", "Show the MSVC and Windows SDK libraries selected by the compiler");
        addInfoEntry(entries, "--workspace <path>", "Also show this workspace's output, intermediate, and dependency folders", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--workspace-module <name>", "Show output and intermediate folders for one workspace module", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--module <path>", "Also show this module's output and intermediate folders", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Inspection", "Read the installation without compiling sources or creating folders");
        Logger::printFieldGroup(ctx, "Reports", entries, nextHelpGroupStyle(hasPrintedGroup, 24));
        return;
    }

    if (command == "new")
    {
        entries.clear();
        addInfoEntry(entries, "script", "Create a runnable Hello World script; default path: hello.swgs", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "script path", "Add .swgs when the path has no extension", LogColor::Reset, 0, LogColor::Dim);
        addInfoEntry(entries, "module", "Create an executable module in a new workspace named after the module", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--workspace", "Create or extend the workspace at this path", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Existing paths", "Stop without overwriting files or modules", LogColor::Reset, 0, LogColor::Dim);
        Logger::printFieldGroup(ctx, "Creates", entries, nextHelpGroupStyle(hasPrintedGroup, 20));

        entries.clear();
        addInfoEntry(entries, "Script", "swc new script hello", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "New workspace", "swc new module hello", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Existing workspace", "swc new module tools --workspace hello", LogColor::Reset, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Examples", entries, nextHelpGroupStyle(hasPrintedGroup, 20));
        return;
    }

    if (command == "clean")
    {
        entries.clear();
        addInfoEntry(entries, "--workspace", "Remove the .output, .tmp, and .dep directories of that workspace", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--workspace-module", "Restrict the removal to one module, keeping the .dep directory the workspace shares", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--module", "Remove the .output and .tmp directories under that module root, and --out-dir and --work-dir when they are set", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--cache", "Remove dependency copies and binary compiler caches kept outside workspaces", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--cache-days", "Keep the copies a run has used within that many days", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "--dry-run", "Report what each target holds and remove nothing", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Absent paths", "Count as already clean", LogColor::Reset, 0, LogColor::Dim);
        Logger::printFieldGroup(ctx, "Removes", entries, nextHelpGroupStyle(hasPrintedGroup, 20));

        entries.clear();
        addInfoEntry(entries, "Workspace", "swc clean --workspace bin/std", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "One module", "swc clean --workspace bin/std --workspace-module core", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Script copies", "swc clean --cache", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Stale copies", "swc clean --cache --cache-days 7", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Preview", "swc clean --workspace bin/std --dry-run", LogColor::Reset, 0, helpArgumentLabelColor());
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

        addInfoEntry(groupEntries, entry.displayName, entry.arg->description, LogColor::Reset, 0, helpArgumentLabelColor());
        if (entry.arg->isEnum())
        {
            addInfoEntry(groupEntries, "choices", Utf8Helper::join(entry.arg->choices, ", "), LogColor::Gray, 1, LogColor::Dim);
        }
        addInfoEntry(groupEntries, "default", defaultValueToString(*entry.arg), LogColor::Gray, 1, LogColor::Dim);
    }

    if (!groupEntries.empty())
        Logger::printFieldGroup(ctx, helpOptionGroupName(currentGroup), groupEntries, nextHelpGroupStyle(hasPrintedGroup, 34));

    if (command == "service")
    {
        entries.clear();
        addInfoEntry(entries, "Launch", "swc service --module <path> --editor-overlay <buffers> --editor-index <snapshot>", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Transport", "Protocol 1: UTF-8 lines on stdin; READY and request markers appear on both output streams", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Analyze", "Send analyze<TAB><id> followed by a newline; await matching SWAG-EDITOR-SERVICE<TAB>1<TAB><id><TAB><exit-code> markers on both streams", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Shutdown", "Send shutdown and a newline, or close stdin; compiler output may appear between marker lines", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Overlay", "SWAG-EDITOR-1 followed by repeated decimal-byte-length/newline/UTF-8 path and buffer pairs", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "Snapshot", "Version 1 JSON at --editor-index; complete is false when analysis reports errors", LogColor::Reset, 0, helpArgumentLabelColor());
        addInfoEntry(entries, "LSP", "Other IDEs can launch node <extension>/src/server.js --stdio; see vscode/README.md", LogColor::Reset, 0, helpArgumentLabelColor());
        Logger::printFieldGroup(ctx, "Editor service protocol", entries, nextHelpGroupStyle(hasPrintedGroup, 24));
    }

    command_ = oldCommand;
}

SWC_END_NAMESPACE();
