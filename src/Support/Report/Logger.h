#pragma once

SWC_BEGIN_NAMESPACE();

enum class LogColor;
class TaskContext;

class Logger
{
public:
    static constexpr size_t ANIMATED_STAGE_FRAME_COUNT = 4;

    Logger();
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
    void   startTransientLine() { transientLineActive_ = true; }
    void   finishTransientLine() { transientLineActive_ = false; }
    void   resetStageSequence();
    size_t nextStageSequence() { return ++stageSequence_; }
    bool   tryClaimUniqueStage(std::string_view key);
    size_t beginAnimatedStage(std::array<Utf8, ANIMATED_STAGE_FRAME_COUNT> lines, std::array<Utf8, ANIMATED_STAGE_FRAME_COUNT> glyphs);
    void   endAnimatedStage(const TaskContext& ctx, size_t stageId, std::string_view finalLine);
    void   pushStageMute() { stageMuteDepth_++; }
    void   popStageMute()
    {
        SWC_ASSERT(stageMuteDepth_ != 0);
        stageMuteDepth_--;
    }
    bool stageOutputMuted() const { return stageMuteDepth_ != 0; }
    void ensureTransientLineSeparated(const TaskContext& ctx, bool blankLine = false);

    static void print(const TaskContext& ctx, std::string_view message);
    static void printDim(const TaskContext& ctx, std::string_view message);
    static void printStdErr(LogColor color, std::string_view message, bool resetColor = true);
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 60);
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, LogColor dotColor, std::string_view dot, size_t messageColumn = 60);
    static void printHeaderCentered(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn = 24);
    static void printAction(const TaskContext& ctx, std::string_view left, std::string_view right);

private:
    struct AnimatedStage
    {
        size_t                                       id         = 0;
        std::array<Utf8, ANIMATED_STAGE_FRAME_COUNT> lines      = {};
        std::array<Utf8, ANIMATED_STAGE_FRAME_COUNT> glyphs     = {};
        size_t                                       frameIndex = 0;
    };

    void animateLoop();
    void clearAnimatedStagesNoLock(bool restoreCursor = true);
    void renderAnimatedStagesNoLock();
    void setCursorVisibleNoLock(bool visible);
    void updateAnimatedStageGlyphsNoLock();
    void removeAnimatedStageNoLock(size_t stageId);

    std::recursive_mutex      mutexAccess_;
    std::vector<AnimatedStage> animatedStages_;
    std::thread               animator_;
    std::atomic<bool>         stopAnimator_            = false;
    bool                      transientLineActive_     = false;
    bool                      activeStagesWereVisible_ = false;
    bool                      cursorHidden_            = false;
    std::vector<Utf8>         uniqueStageKeys_;
    size_t                    renderedStageCount_      = 0;
    size_t                    outputBlockDepth_        = 0;
    size_t                    stageSequence_           = 0;
    size_t                    stageMuteDepth_          = 0;
    size_t                    nextAnimatedStageId_     = 0;
};

SWC_END_NAMESPACE();
