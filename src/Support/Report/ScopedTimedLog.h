#pragma once
#include "Support/Core/Utf8.h"

struct TaskContext;

SWC_BEGIN_NAMESPACE();

// A scoped stage times the work done in its lifetime and prints one summary line on destruction.
class ScopedTimedLog
{
public:
    using Clock = std::chrono::steady_clock;

    enum class Stage : uint8_t
    {
        Workspace,
        Module,
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
        size_t   numTests                = 0;
        size_t   numTokens               = 0;
        size_t   numFormatRewrittenFiles = 0;

        static StatsSnapshot capture();
    };

    explicit ScopedTimedLog(const TaskContext& ctx, Stage stage, Utf8 detail = {});
    ~ScopedTimedLog();

    ScopedTimedLog(const ScopedTimedLog&)            = delete;
    ScopedTimedLog& operator=(const ScopedTimedLog&) = delete;

    StatsSnapshot delta() const;
    void          markFailure();
    void          markUpToDate();
    void          setStat(Utf8 stat);

    // Small helpers callers use to assemble the parts of a stage line.
    static Utf8 formatStatCount(const TaskContext& ctx, size_t value, std::string_view singular, const char* pluralForm = nullptr);
    static Utf8 formatStatRatio(const TaskContext& ctx, size_t value, size_t total, std::string_view singular);
    static Utf8 formatStatName(const TaskContext& ctx, std::string_view name);
    static Utf8 joinStatItems(const TaskContext& ctx, const std::vector<Utf8>& items);
    static bool isOutputEnabled(const TaskContext& ctx, Stage stage);
    static void printCommandHeader(const TaskContext& ctx);

private:
    const TaskContext*          ctx_ = nullptr;
    Stage                       stage_{};
    Clock::time_point           startTick_{};
    StatsSnapshot               startSnapshot_{};
    std::optional<StageOutcome> forcedOutcome_;
    Utf8                        detail_;
    Utf8                        stat_;
    bool                        printEnabled_ = true;
    bool                        upToDate_     = false;
};

SWC_END_NAMESPACE();
