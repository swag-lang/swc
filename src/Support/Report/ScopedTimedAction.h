#pragma once

#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
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

    inline size_t lineSize(std::string_view action, std::string_view detail)
    {
        size_t result = actionLeadingSpaces(action) + action.size();
        if (!detail.empty())
            result += 1 + detail.size();
        return result;
    }

    inline void printLine(const TaskContext& ctx, std::string_view action, std::string_view detail, std::string_view elapsedTime, const bool endLine)
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

        if (!elapsedTime.empty())
        {
            Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Gray));
            Logger::print(ctx, " ");
            Logger::print(ctx, elapsedTime);
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
        detail_(detail),
        lineSize_(TimedActionLog::lineSize(action_, detail_)),
        startTime_(Timer::Clock::now())
    {
        const Logger::ScopedLock loggerLock(ctx.global().logger());
        TimedActionLog::printLine(ctx, action_, detail_, {}, false);
    }

    void success()
    {
        if (!active_)
            return;

        const Utf8 elapsed = Utf8Helper::toNiceTime(std::chrono::duration<double>(Timer::Clock::now() - startTime_).count());
        const Logger::ScopedLock loggerLock(ctx_->global().logger());
        Logger::print(*ctx_, "\r");
        TimedActionLog::printLine(*ctx_, action_, detail_, elapsed, true);
        active_ = false;
    }

    void fail()
    {
        if (!active_)
            return;

        const Logger::ScopedLock loggerLock(ctx_->global().logger());
        Logger::print(*ctx_, "\r");
        Logger::print(*ctx_, std::string(lineSize_, ' '));
        Logger::print(*ctx_, "\r");
        std::cout << std::flush;
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
    size_t             lineSize_  = 0;
    Timer::Tick        startTime_{};
    bool               active_    = true;
};

SWC_END_NAMESPACE();
