#pragma once

#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class Logger
{
public:
    struct FieldEntry
    {
        Utf8     label;
        Utf8     value;
        LogColor labelColor = LogColor::Gray;
        LogColor valueColor = LogColor::White;
        uint32_t indentLevel = 0;
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

    Logger()  = default;
    ~Logger() = default;

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

    void lock();
    void unlock();
    void resetStageClaims();
    bool claimStageOnce(std::string_view key);
    void pushStageMute() { stageMuteDepth_++; }
    void popStageMute()
    {
        SWC_ASSERT(stageMuteDepth_ != 0);
        stageMuteDepth_--;
    }
    bool stageOutputMuted() const { return stageMuteDepth_ != 0; }

    static void print(const TaskContext& ctx, std::string_view message);
    static void printDim(const TaskContext& ctx, std::string_view message);
    static void printStdErr(LogColor color, std::string_view message, bool resetColor = true);
    static void printField(const TaskContext& ctx, const FieldEntry& entry, FieldGroupStyle style = FieldGroupStyle{});
    static void printFieldGroup(const TaskContext& ctx, std::string_view title, const std::vector<FieldEntry>& entries, FieldGroupStyle style = FieldGroupStyle{});
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot = ".", size_t messageColumn = 60);
    static void printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, LogColor dotColor, std::string_view dot, size_t messageColumn = 60);
    static void printHeaderCentered(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn = 24);
    static void printAction(const TaskContext& ctx, std::string_view left, std::string_view right);

private:
    std::recursive_mutex mutexAccess_;
    std::vector<Utf8>    claimedStageKeys_;
    size_t               stageMuteDepth_ = 0;
};

SWC_END_NAMESPACE();
