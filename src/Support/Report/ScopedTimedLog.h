#pragma once
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

struct TaskContext;

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

// A scoped stage times the work done in its lifetime and prints one summary line on destruction:
// '<stage> <outcome>: <part>, <part>', where the outcome is ok, up-to-date, warning or error.
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
        Doc,
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
        size_t numErrors               = 0;
        size_t numWarnings             = 0;
        size_t numFiles                = 0;
        size_t numTests                = 0;
        size_t numTestsFailed          = 0;
        size_t numTokens               = 0;
        size_t numFormatRewrittenFiles = 0;

        static StatsSnapshot capture();
    };

    explicit ScopedTimedLog(const TaskContext& ctx, Stage stage, Utf8 detail = {});
    ~ScopedTimedLog();

    ScopedTimedLog(const ScopedTimedLog&)            = delete;
    ScopedTimedLog& operator=(const ScopedTimedLog&) = delete;

    StatsSnapshot delta() const;
    void          dismiss();
    void          markFailure();
    void          markUpToDate();

    void setStat(Utf8 stat);

    static void appendTestStats(std::vector<Utf8>& parts, size_t executed, size_t failed);
    static Utf8 formatTestLocation(const TaskContext& ctx, const SymbolFunction& function);

    static Utf8 formatStatCount(size_t value, std::string_view singular, const char* pluralForm = nullptr);
    static Utf8 formatStatRatio(size_t value, size_t total, std::string_view singular);
    static Utf8 joinStatItems(const std::vector<Utf8>& items);

    static bool isOutputEnabled(const TaskContext& ctx, Stage stage);

private:
    const TaskContext*          ctx_ = nullptr;
    Stage                       stage_{};
    Clock::time_point           startTick_{};
    StatsSnapshot               startSnapshot_{};
    std::optional<StageOutcome> forcedOutcome_;

    Utf8 detail_;
    Utf8 stat_;

    bool printEnabled_ = true;
    bool upToDate_     = false;
};

// Brackets a whole command: one closing line names it and signs the run off with its outcome
// and the wall time of the process.
class ScopedCommandLog
{
public:
    explicit ScopedCommandLog(const TaskContext& ctx);
    ~ScopedCommandLog();

    ScopedCommandLog(const ScopedCommandLog&)            = delete;
    ScopedCommandLog& operator=(const ScopedCommandLog&) = delete;

private:
    const TaskContext*                ctx_ = nullptr;
    ScopedTimedLog::Clock::time_point startTick_{};
};

SWC_END_NAMESPACE();
