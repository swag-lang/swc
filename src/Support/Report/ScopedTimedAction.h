#pragma once

#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace TimedActionLog
{
    constexpr size_t ACTION_CENTER_COLUMN = 24;

    inline size_t actionLeadingSpaces(std::string_view action)
    {
        if (action.size() >= ACTION_CENTER_COLUMN)
            return 0;
        return ACTION_CENTER_COLUMN - action.size();
    }

    inline void printLine(const TaskContext& ctx, std::string_view action, std::string_view detail, const bool endLine)
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
            Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::White));
            Logger::print(ctx, detail);
        }

        Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Reset));
        if (endLine)
            Logger::print(ctx, "\n");

        std::cout << std::flush;
    }
}

class ScopedTimedAction
{
public:
    explicit ScopedTimedAction(const TaskContext& ctx, std::string_view action, std::string_view detail = {}) :
        ctx_(&ctx),
        action_(action),
        detail_(detail)
    {
        const Logger::ScopedLock loggerLock(ctx.global().logger());
        TimedActionLog::printLine(ctx, action_, detail_, true);
    }

    void success()
    {
        if (!active_)
            return;

        active_ = false;
    }

    void fail()
    {
        if (!active_)
            return;

        active_ = false;
    }

    ~ScopedTimedAction()
    {
        fail();
    }

private:
    const TaskContext* ctx_       = nullptr;
    Utf8               action_;
    Utf8               detail_;
    bool               active_    = true;
};

SWC_END_NAMESPACE();
