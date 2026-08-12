#pragma once
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class Logger
{
public:
    static constexpr size_t PROGRESS_FRAME_COUNT = 4;
    using ProgressFrames                         = std::array<Utf8, PROGRESS_FRAME_COUNT>;

    struct FieldValuePart
    {
        Utf8     text;
        LogColor color = LogColor::Reset;
    };

    struct FieldEntry
    {
        Utf8                        label;
        Utf8                        value;
        std::vector<FieldValuePart> valueParts;
        LogColor                    labelColor  = LogColor::Gray;
        LogColor                    valueColor  = LogColor::White;
        uint32_t                    indentLevel = 0;
    };

    struct FieldGroupStyle
    {
        LogColor titleColor        = LogColor::BrightCyan;
        LogColor defaultLabelColor = LogColor::Gray;
        LogColor defaultValueColor = LogColor::White;
        size_t   lineIndent        = 2;
        size_t   indentPerLevel    = 2;
        size_t   minLabelWidth     = 16;
        size_t   maxLabelWidth     = 28;
        size_t   maxLineWidth      = 108;
        bool     blankLineBefore   = true;
        bool     blankLineAfter    = false;
    };

    Logger() = default;
    ~Logger();

    class ScopedStageMute
    {
    public:
        explicit ScopedStageMute(Logger& logger) :
            logger_(&logger)
        {
            logger_->pushStageMute();
        }

        ~ScopedStageMute()
        {
            if (logger_)
                logger_->popStageMute();
        }

        ScopedStageMute(const ScopedStageMute&)            = delete;
        ScopedStageMute& operator=(const ScopedStageMute&) = delete;

    private:
        Logger* logger_ = nullptr;
    };

    class ScopedStageOutputUnmute
    {
    public:
        explicit ScopedStageOutputUnmute(Logger& logger) :
            logger_(&logger),
            savedStageMuteDepth_(logger.stageMuteDepth_)
        {
            logger_->stageMuteDepth_ = 0;
        }

        ~ScopedStageOutputUnmute()
        {
            if (logger_)
                logger_->stageMuteDepth_ = savedStageMuteDepth_;
        }

        ScopedStageOutputUnmute(const ScopedStageOutputUnmute&)            = delete;
        ScopedStageOutputUnmute& operator=(const ScopedStageOutputUnmute&) = delete;

    private:
        Logger* logger_              = nullptr;
        size_t  savedStageMuteDepth_ = 0;
    };

    // Detail is a per-run choice, and runs nest: a dependency built on demand starts a whole
    // workspace build inside an enclosing command. The nested run decides its own verbosity, and
    // this scope is what keeps that decision from silencing the run that triggered it.
    class ScopedStagesDetailed
    {
    public:
        ScopedStagesDetailed(Logger& logger, const bool detailed) :
            logger_(&logger),
            savedStagesDetailed_(logger.stagesDetailed_)
        {
            logger_->stagesDetailed_ = detailed;
        }

        ~ScopedStagesDetailed()
        {
            if (logger_)
                logger_->stagesDetailed_ = savedStagesDetailed_;
        }

        ScopedStagesDetailed(const ScopedStagesDetailed&)            = delete;
        ScopedStagesDetailed& operator=(const ScopedStagesDetailed&) = delete;

    private:
        Logger* logger_              = nullptr;
        bool    savedStagesDetailed_ = false;
    };

    class ScopedLock
    {
    public:
        explicit ScopedLock(Logger& logger) :
            logger_(&logger)
        {
            logger_->lock();
        }

        ~ScopedLock()
        {
            if (logger_)
                logger_->unlock();
        }

        ScopedLock(const ScopedLock&)            = delete;
        ScopedLock& operator=(const ScopedLock&) = delete;

    private:
        Logger* logger_ = nullptr;
    };

    void   lock();
    void   unlock();
    size_t beginProgress(ProgressFrames frames);
    void   updateProgress(size_t progressId, ProgressFrames frames);
    void   endProgress(size_t progressId, std::string_view finalLine);
    void   cancelProgress(size_t progressId);
    void   resetStageClaims();
    bool   claimStageOnce(std::string_view key);
    void   pushStageMute() { stageMuteDepth_++; }
    void   popStageMute()
    {
        SWC_ASSERT(stageMuteDepth_ != 0);
        stageMuteDepth_--;
    }
    bool stageOutputMuted() const { return stageMuteDepth_ != 0; }

    // Detailed stages let every compilation phase report itself instead of hiding behind one
    // command-level summary. Only a run with a single target turns them on: repeated per module,
    // the cascade would bury the workspace output.
    void setStagesDetailed(bool detailed) { stagesDetailed_ = detailed; }
    bool stagesDetailed() const { return stagesDetailed_; }

    static void print(const TaskContext& ctx, std::string_view message);
    static void printDim(const TaskContext& ctx, std::string_view message);
    static void printStdErr(LogColor color, std::string_view message, bool resetColor = true);
    static void printField(const TaskContext& ctx, const FieldEntry& entry, const FieldGroupStyle& style = FieldGroupStyle{});
    static void printFieldGroup(const TaskContext& ctx, std::string_view title, const std::vector<FieldEntry>& entries, const FieldGroupStyle& style = FieldGroupStyle{});
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 60);
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, LogColor dotColor, std::string_view dot, size_t messageColumn = 60);
    static void printHeaderCentered(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn = 24);
    static void printAction(const TaskContext& ctx, std::string_view left, std::string_view right);

private:
    struct ActiveProgress
    {
        size_t                                id = 0;
        ProgressFrames                        frames;
        std::chrono::steady_clock::time_point startTick;
        size_t                                frameIndex = 0;
    };

    void animateLoop();
    void clearProgressNoLock();
    void renderProgressNoLock();
    void showCursorNoLock();

    std::recursive_mutex        mutexAccess_;
    std::mutex                  animatorWakeMutex_;
    std::condition_variable     animatorWake_;
    std::vector<ActiveProgress> activeProgress_;
    std::thread                 animator_;
    std::vector<Utf8>           claimedStageKeys_;
    std::atomic<bool>           stopAnimator_      = false;
    size_t                      outputBlockDepth_  = 0;
    size_t                      stageMuteDepth_    = 0;
    size_t                      nextProgressId_    = 0;
    bool                        progressRendered_  = false;
    bool                        cursorHidden_      = false;
    bool                        permanentLineOpen_ = false;
    bool                        stagesDetailed_    = false;
};

SWC_END_NAMESPACE();
