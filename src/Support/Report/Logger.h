#pragma once
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class Logger
{
public:
    struct FieldEntry
    {
        Utf8     label;
        Utf8     value;
        uint32_t indentLevel = 0;
    };

    Logger() = default;

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

    void lock() { mutexAccess_.lock(); }
    void unlock() { mutexAccess_.unlock(); }

    void resetStageClaims();
    bool claimStageOnce(std::string_view key);

    void pushStageMute() { stageMuteDepth_++; }
    void popStageMute()
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
    static void printAndFlush(const TaskContext& ctx, std::string_view message);
    static void printStdErr(std::string_view message);

    // A field prints as 'label: value', or as its value alone without a label, indented two spaces
    // per level. A group prints its title on its own line first; its entries then start one level in.
    static void printField(const TaskContext& ctx, const FieldEntry& entry);
    static void printFieldGroup(const TaskContext& ctx, std::string_view title, const std::vector<FieldEntry>& entries);

private:
    std::recursive_mutex mutexAccess_;
    std::vector<Utf8>    claimedStageKeys_;

    size_t stageMuteDepth_ = 0;
    bool   stagesDetailed_ = false;
};

SWC_END_NAMESPACE();
