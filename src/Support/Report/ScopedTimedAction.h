#pragma once

#include "Main/Global.h"
#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace TimedActionLog
{
    constexpr size_t ACTION_CENTER_COLUMN = 24;

    inline Utf8 buildCfgBackendKindName(const Runtime::BuildCfgBackendKind value)
    {
        switch (value)
        {
            case Runtime::BuildCfgBackendKind::Executable:
                return "exe";
            case Runtime::BuildCfgBackendKind::Library:
                return "dll";
            case Runtime::BuildCfgBackendKind::Export:
                return "lib";
            case Runtime::BuildCfgBackendKind::None:
                return "none";
        }

        SWC_UNREACHABLE();
    }

    inline Utf8 formatBuildConfiguration(const TaskContext& ctx)
    {
        const CommandLine&       cmdLine  = ctx.cmdLine();
        const Runtime::BuildCfg& buildCfg = cmdLine.defaultBuildCfg;
        return std::format("{} ({})", cmdLine.buildCfg, buildCfgBackendKindName(buildCfg.backendKind));
    }

    inline size_t actionLeadingSpaces(std::string_view action)
    {
        if (action.size() >= ACTION_CENTER_COLUMN)
            return 0;
        return ACTION_CENTER_COLUMN - action.size();
    }

    inline void printAction(const TaskContext& ctx, std::string_view action, std::string_view detail = {})
    {
        if (ctx.cmdLine().silent)
            return;

        for (size_t i = 0; i < actionLeadingSpaces(action); ++i)
            Logger::print(ctx, " ");

        Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Green));
        Logger::print(ctx, action);

        if (!detail.empty())
        {
            Logger::print(ctx, " ");
            const size_t parenPos = detail.find('(');
            if (parenPos == std::string_view::npos)
            {
                Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::White));
                Logger::print(ctx, detail);
            }
            else
            {
                const std::string_view prefix = detail.substr(0, parenPos);
                const std::string_view suffix = detail.substr(parenPos);
                if (!prefix.empty())
                {
                    Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::White));
                    Logger::print(ctx, prefix);
                }

                Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Gray));
                Logger::print(ctx, suffix);
            }
        }

        Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Reset));
        Logger::print(ctx, "\n");

        std::cout << std::flush;
    }

    inline void printBuildConfiguration(const TaskContext& ctx)
    {
        const Logger::ScopedLock loggerLock(ctx.global().logger());
        printAction(ctx, "BuildCfg", formatBuildConfiguration(ctx));
    }

    inline void printStep(const TaskContext& ctx, std::string_view action, std::string_view detail = {})
    {
        const Logger::ScopedLock loggerLock(ctx.global().logger());
        printAction(ctx, action, detail);
    }
}

SWC_END_NAMESPACE();
