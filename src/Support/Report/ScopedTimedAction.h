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

#if SWC_HAS_STATS
        uint64_t timeLoadFile   = 0;
        uint64_t timeLexer      = 0;
        uint64_t timeParser     = 0;
        uint64_t timeSema       = 0;
        uint64_t timeCodeGen    = 0;
        uint64_t timeMicroLower = 0;

        size_t numFiles             = 0;
        size_t numTokens            = 0;
        size_t numAstNodes          = 0;
        size_t numVisitedAstNodes   = 0;
        size_t numConstants         = 0;
        size_t numTypes             = 0;
        size_t numIdentifiers       = 0;
        size_t numSymbols           = 0;
        size_t numMicroInstrNoOptim = 0;
        size_t numMicroInstrFinal   = 0;
        size_t numCodeGenFunctions  = 0;
#endif

        static StatsSnapshot capture();
    };

    struct StageSpec
    {
        Utf8 key;
        Utf8 label;
        Utf8 verb;
        Utf8 detail;
    };

    Utf8 formatStageStartLine(const TaskContext& ctx, const StageSpec& spec, size_t sequence);
    Utf8 formatStageEndLine(const TaskContext&   ctx,
                            const StageSpec&     spec,
                            size_t               sequence,
                            StageOutcome         outcome,
                            const StatsSnapshot& before,
                            const StatsSnapshot& after,
                            uint64_t             durationNs);

    void printBuildConfiguration(const TaskContext& ctx);
    void printSessionFlags(const TaskContext& ctx);

    class ScopedStage
    {
    public:
        ScopedStage(const TaskContext& ctx, StageSpec spec);
        ~ScopedStage();

        ScopedStage(const ScopedStage&)            = delete;
        ScopedStage& operator=(const ScopedStage&) = delete;

        void markOutcome(StageOutcome outcome);
        void markFailure();
        void markWarning();

    private:
        const TaskContext*          ctx_ = nullptr;
        StageSpec                   spec_;
        StatsSnapshot               before_;
        Clock::time_point           startTick_{};
        size_t                      sequence_ = 0;
        std::optional<StageOutcome> forcedOutcome_;
    };

    Utf8 formatSummaryLine(const TaskContext& ctx, const StatsSnapshot& snapshot);
    void printSummary(const TaskContext& ctx);
    void printStep(const TaskContext& ctx, std::string_view action, std::string_view detail = {});
}

SWC_END_NAMESPACE();
