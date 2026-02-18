#include "pch.h"
#include "Main/CommandLineParser.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

struct HelpOptionEntry
{
    const ArgInfo*  arg = nullptr;
    Utf8            displayName;
    HelpOptionGroup group = HelpOptionGroup::Other;
};

namespace
{
    Utf8 formatPathValue(const fs::path& value)
    {
        if (value.empty())
            return {};

        return value.string();
    }

    Utf8 formatStringSetValue(const std::set<Utf8>& values)
    {
        if (values.empty())
            return {};

        Utf8 result;
        bool first = true;
        for (const auto& value : values)
        {
            if (!first)
                result += ", ";
            result += value;
            first = false;
        }

        return result;
    }

    Utf8 formatPathSetValue(const std::set<fs::path>& values)
    {
        if (values.empty())
            return {};

        Utf8 result;
        bool first = true;
        for (const auto& value : values)
        {
            if (!first)
                result += ", ";
            result += value.string();
            first = false;
        }

        return result;
    }

    Utf8 enumValueFromIndex(const Utf8& enumValues, int index)
    {
        if (enumValues.empty())
            return std::to_string(index);

        std::istringstream iss(enumValues);
        Utf8               value;
        int                currentIndex = 0;
        while (std::getline(iss, value, '|'))
        {
            if (currentIndex == index)
                return value;

            currentIndex++;
        }

        return std::to_string(index);
    }

    Utf8 formatEnumChoices(const Utf8& enumValues)
    {
        Utf8               result;
        std::istringstream iss(enumValues);
        Utf8               value;
        bool               first = true;
        while (std::getline(iss, value, '|'))
        {
            if (!first)
                result += ", ";
            result += value;
            first = false;
        }

        return result;
    }

    bool hasDisplayableDefaultValue(const ArgInfo& arg)
    {
        switch (arg.type)
        {
            case CommandLineType::String:
                return !static_cast<const Utf8*>(arg.target)->empty();

            case CommandLineType::Path:
                return !static_cast<const fs::path*>(arg.target)->empty();

            case CommandLineType::StringSet:
                return !static_cast<const std::set<Utf8>*>(arg.target)->empty();

            case CommandLineType::PathSet:
                return !static_cast<const std::set<fs::path>*>(arg.target)->empty();

            case CommandLineType::EnumString:
                return !static_cast<const Utf8*>(arg.target)->empty();

            default:
                return true;
        }
    }

    Utf8 defaultValueToString(const ArgInfo& arg)
    {
        switch (arg.type)
        {
            case CommandLineType::Bool:
                return *static_cast<const bool*>(arg.target) ? "true" : "false";

            case CommandLineType::Int:
                return std::to_string(*static_cast<const int*>(arg.target));

            case CommandLineType::UnsignedInt:
                return std::to_string(*static_cast<const uint32_t*>(arg.target));

            case CommandLineType::String:
                return *static_cast<const Utf8*>(arg.target);

            case CommandLineType::Path:
                return formatPathValue(*static_cast<const fs::path*>(arg.target));

            case CommandLineType::StringSet:
                return formatStringSetValue(*static_cast<const std::set<Utf8>*>(arg.target));

            case CommandLineType::PathSet:
                return formatPathSetValue(*static_cast<const std::set<fs::path>*>(arg.target));

            case CommandLineType::EnumString:
                return *static_cast<const Utf8*>(arg.target);

            case CommandLineType::EnumInt:
                return enumValueFromIndex(arg.enumValues, *static_cast<const int*>(arg.target));
        }

        return "<unknown>";
    }

    Utf8 makeOptionDisplayName(const ArgInfo& arg)
    {
        Utf8 name = arg.longForm;
        if (!arg.shortForm.empty())
        {
            name += ", ";
            name += arg.shortForm;
        }

        return name;
    }

    int optionGroupOrder(HelpOptionGroup group)
    {
        return static_cast<int>(group);
    }

    const char* optionGroupName(HelpOptionGroup group)
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
            case HelpOptionGroup::LoggingAndOutput:
                return "Logging/Output";
            case HelpOptionGroup::Testing:
                return "Testing";
            case HelpOptionGroup::Development:
                return "Development";
            case HelpOptionGroup::Other:
                return "Other";
        }

        return "Other";
    }

    bool optionEntryLess(const HelpOptionEntry& lhs, const HelpOptionEntry& rhs)
    {
        const int leftOrder  = optionGroupOrder(lhs.group);
        const int rightOrder = optionGroupOrder(rhs.group);
        if (leftOrder != rightOrder)
            return leftOrder < rightOrder;

        if (lhs.displayName != rhs.displayName)
            return lhs.displayName < rhs.displayName;

        return lhs.arg->description < rhs.arg->description;
    }

    bool commandInfoLess(const CommandInfo& lhs, const CommandInfo& rhs)
    {
        return Utf8(lhs.name) < Utf8(rhs.name);
    }

    Utf8 colorize(const TaskContext& ctx, LogColor color, std::string_view text)
    {
        Utf8 result;
        result += LogColorHelper::toAnsi(ctx, color);
        result += text;
        result += LogColorHelper::toAnsi(ctx, LogColor::Reset);
        return result;
    }
}

void CommandLineParser::printHelp(const TaskContext& ctx, const Utf8& command)
{
    Logger::ScopedLock loggerLock(ctx.global().logger());
    Logger::printDim(ctx, std::format("swc: swag compiler version {}.{}.{}\n", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
    Logger::printDim(ctx, "Usage:\n");

    if (command.empty())
    {
        Logger::printDim(ctx, "    swc <command> [options]\n");
        Logger::printDim(ctx, "    swc help <command>\n\n");

        Logger::printDim(ctx, "Commands:\n");
        std::vector<CommandInfo> commands(std::begin(COMMANDS), std::end(COMMANDS));
        std::ranges::sort(commands, commandInfoLess);

        size_t maxLen = 0;
        for (const auto& cmd : commands)
            maxLen = std::max(maxLen, strlen(cmd.name));
        for (const auto& cmd : commands)
            Logger::printDim(ctx, std::format("    {:<{}}    {}\n", cmd.name, maxLen, cmd.description));
    }
    else
    {
        Logger::printDim(ctx, std::format("    swc {} [options]\n\n", command));
        Logger::printDim(ctx, "Options:\n");

        const Utf8 oldCommand = command_;
        command_              = command;

        std::vector<HelpOptionEntry> entries;
        entries.reserve(args_.size());
        for (const auto& arg : args_)
        {
            if (!commandMatches(arg.commands))
                continue;

            HelpOptionEntry entry;
            entry.arg         = &arg;
            entry.displayName = makeOptionDisplayName(arg);
            entry.group       = arg.group;
            entries.push_back(std::move(entry));
        }
        std::ranges::sort(entries, optionEntryLess);

        size_t maxLen = 0;
        for (const auto& entry : entries)
        {
            maxLen = std::max(maxLen, entry.displayName.length());
        }

        HelpOptionGroup currentGroup = HelpOptionGroup::Other;
        bool firstGroup   = true;
        for (const auto& entry : entries)
        {
            if (firstGroup || currentGroup != entry.group)
            {
                if (!firstGroup)
                    Logger::printDim(ctx, "\n");

                Logger::printDim(ctx, std::format("  {}:\n", optionGroupName(entry.group)));
                currentGroup = entry.group;
                firstGroup   = false;
            }

            Utf8 line = "    ";
            line += colorize(ctx, LogColor::BrightCyan, std::format("{:<{}}", entry.displayName, maxLen));
            line += "    ";
            line += entry.arg->description;
            Logger::print(ctx, line);
            Logger::print(ctx, "\n");

            const Utf8 metadataPrefix = std::format("    {:<{}}    ", "", maxLen);
            if ((entry.arg->type == CommandLineType::EnumString || entry.arg->type == CommandLineType::EnumInt) && !entry.arg->enumValues.empty())
            {
                Utf8 choiceLine = metadataPrefix;
                choiceLine += colorize(ctx, LogColor::Dim, "choices:");
                choiceLine += " ";
                choiceLine += colorize(ctx, LogColor::Yellow, formatEnumChoices(entry.arg->enumValues));
                Logger::print(ctx, choiceLine);
                Logger::print(ctx, "\n");
            }

            if (hasDisplayableDefaultValue(*entry.arg))
            {
                Utf8 defaultLine = metadataPrefix;
                defaultLine += colorize(ctx, LogColor::Dim, "default:");
                defaultLine += " ";
                defaultLine += colorize(ctx, LogColor::BrightGreen, defaultValueToString(*entry.arg));
                Logger::print(ctx, defaultLine);
                Logger::print(ctx, "\n");
            }
        }

        command_ = oldCommand;
    }
}

SWC_END_NAMESPACE();
