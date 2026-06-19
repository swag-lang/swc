#pragma once

#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

namespace TimedActionLog
{
    using Clock = std::chrono::steady_clock;

    enum class Stage : uint8_t
    {
        Workspace,
        Module,
        Config,
        Modes,
        Format,
        Syntax,
        Sema,
        JIT,
        Micro,
        Build,
        Run,
        Test,
        Verify,
        Unittest,
    };

    enum class StageOutcome : uint8_t
    {
        Success = 0,
        Warning = 1,
        Error   = 2,
    };

    struct StatsSnapshot
    {
        uint64_t timeTotal               = 0;
        size_t   numErrors               = 0;
        size_t   numWarnings             = 0;
        size_t   numFiles                = 0;
        size_t   numTokens               = 0;
        size_t   numFormatRewrittenFiles = 0;

        static StatsSnapshot capture();
    };

    void printBuildConfiguration(const TaskContext& ctx);
    void printSessionFlags(const TaskContext& ctx);

    class ScopedStage
    {
    public:
        explicit ScopedStage(const TaskContext& ctx, Stage stage, Utf8 detail = {});
        ~ScopedStage();

        ScopedStage(const ScopedStage&)            = delete;
        ScopedStage& operator=(const ScopedStage&) = delete;

        StatsSnapshot delta() const;
        void          markOutcome(StageOutcome outcome);
        void          markFailure();
        void          markWarning();
        void          setStat(Utf8 stat);

    private:
        const TaskContext*          ctx_ = nullptr;
        Stage                       stage_{};
        Clock::time_point           startTick_{};
        StatsSnapshot               startSnapshot_{};
        std::optional<StageOutcome> forcedOutcome_;
        Utf8                        detail_;
        Utf8                        stat_;
        bool                        printEnabled_ = true;
    };

    Utf8 formatCommandHeaderLine(const TaskContext& ctx);
    Utf8 formatStatText(const TaskContext& ctx, std::string_view text, LogColor color = LogColor::White);
    Utf8 formatStatCount(const TaskContext& ctx, size_t value, std::string_view singular, const char* plural = nullptr, LogColor color = LogColor::Gray);
    Utf8 formatStatRatio(const TaskContext& ctx, size_t value, size_t total, std::string_view singular, const char* plural = nullptr, LogColor color = LogColor::Gray);
    Utf8 formatStatDuration(const TaskContext& ctx, uint64_t durationNs, LogColor color = LogColor::Gray);
    Utf8 formatStatName(const TaskContext& ctx, std::string_view name, LogColor color = LogColor::Gray);
    Utf8 formatStatEntity(const TaskContext& ctx, std::string_view kind, std::string_view name, LogColor kindColor = LogColor::Gray, LogColor nameColor = LogColor::Yellow);
    Utf8 joinStatItems(const TaskContext& ctx, const std::vector<Utf8>& items);
    void printCommandHeader(const TaskContext& ctx);
    Utf8 formatSummaryLine(const TaskContext& ctx, const StatsSnapshot& snapshot);
    void printSummary(const TaskContext& ctx);
}

SWC_END_NAMESPACE();
