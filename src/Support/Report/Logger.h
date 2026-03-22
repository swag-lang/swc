#pragma once

SWC_BEGIN_NAMESPACE();

enum class LogColor;
class TaskContext;

class Logger
{
public:
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

    void   lock() { mutexAccess_.lock(); }
    void   unlock() { mutexAccess_.unlock(); }
    void   startTransientLine() { transientLineActive_ = true; }
    void   finishTransientLine() { transientLineActive_ = false; }
    void   resetStageSequence() { stageSequence_ = 0; }
    size_t nextStageSequence() { return ++stageSequence_; }
    void   pushStageMute() { stageMuteDepth_++; }
    void   popStageMute()
    {
        SWC_ASSERT(stageMuteDepth_ != 0);
        stageMuteDepth_--;
    }
    bool stageOutputMuted() const { return stageMuteDepth_ != 0; }
    void ensureTransientLineSeparated(const TaskContext& ctx);

    static void print(const TaskContext& ctx, std::string_view message);
    static void printDim(const TaskContext& ctx, std::string_view message);
    static void printStdErr(LogColor color, std::string_view message, bool resetColor = true);
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 60);
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, LogColor dotColor, std::string_view dot, size_t messageColumn = 60);
    static void printHeaderCentered(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn = 24);
    static void printAction(const TaskContext& ctx, std::string_view left, std::string_view right);

private:
    std::mutex mutexAccess_;
    bool       transientLineActive_ = false;
    size_t     stageSequence_       = 0;
    size_t     stageMuteDepth_      = 0;
};

SWC_END_NAMESPACE();
