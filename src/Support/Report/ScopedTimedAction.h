#pragma once

#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace TimedActionLog
{
    using Clock = std::chrono::steady_clock;

    enum class StageOutcome : uint8_t
    {
        Success = 0,
        Warning = 1,
        Error   = 2,
    };

    struct StatsSnapshot
    {
        uint64_t timeTotal   = 0;
        size_t   numErrors   = 0;
        size_t   numWarnings = 0;
        size_t   numFiles    = 0;
        size_t   numTokens   = 0;

        static StatsSnapshot capture();
    };

    void printBuildConfiguration(const TaskContext& ctx);
    void printSessionFlags(const TaskContext& ctx);

    class ScopedStage
    {
    public:
        ScopedStage(const TaskContext& ctx, Utf8 label, Utf8 verb, Utf8 detail = {});
        ~ScopedStage();

        ScopedStage(const ScopedStage&)            = delete;
        ScopedStage& operator=(const ScopedStage&) = delete;

        void markOutcome(StageOutcome outcome);
        void markFailure();
        void markWarning();
        void setStat(Utf8 stat);

    private:
        const TaskContext*          ctx_ = nullptr;
        Utf8                        label_;
        Utf8                        verb_;
        Utf8                        detail_;
        Clock::time_point           startTick_{};
        size_t                      startErrors_   = 0;
        size_t                      startWarnings_ = 0;
        std::optional<StageOutcome> forcedOutcome_;
        Utf8                        stat_;
    };

    Utf8 formatSummaryLine(const TaskContext& ctx, const StatsSnapshot& snapshot);
    void printSummary(const TaskContext& ctx);
}

SWC_END_NAMESPACE();
