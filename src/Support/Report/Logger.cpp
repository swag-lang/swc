#include "pch.h"

#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr auto ANIMATION_INTERVAL = std::chrono::milliseconds(120);

    std::mutex& stdErrMutex()
    {
        static std::mutex mutex;
        return mutex;
    }
}

Logger::Logger()
{
    animator_ = std::thread([this] { animateLoop(); });
}

Logger::~Logger()
{
    stopAnimator_.store(true, std::memory_order_release);
    if (animator_.joinable())
        animator_.join();

    const std::scoped_lock lock(mutexAccess_);
    setCursorVisibleNoLock(true);
}

void Logger::lock()
{
    mutexAccess_.lock();
    if (outputBlockDepth_++ == 0)
    {
        activeStagesWereVisible_ = renderedStageCount_ != 0;
        clearAnimatedStagesNoLock();
    }
}

void Logger::unlock()
{
    SWC_ASSERT(outputBlockDepth_ != 0);
    outputBlockDepth_--;
    if (outputBlockDepth_ == 0)
    {
        renderAnimatedStagesNoLock();
        activeStagesWereVisible_ = false;
    }

    mutexAccess_.unlock();
}

void Logger::resetStageSequence()
{
    const ScopedLock lock(*this);
    stageSequence_ = 0;
    uniqueStageKeys_.clear();
}

bool Logger::tryClaimUniqueStage(const std::string_view key)
{
    const ScopedLock lock(*this);
    for (const Utf8& existingKey : uniqueStageKeys_)
    {
        if (existingKey == key)
            return false;
    }

    uniqueStageKeys_.emplace_back(key);
    return true;
}

size_t Logger::beginAnimatedStage(std::array<Utf8, ANIMATED_STAGE_FRAME_COUNT> lines, std::array<Utf8, ANIMATED_STAGE_FRAME_COUNT> glyphs)
{
    const ScopedLock lock(*this);
    const size_t     stageId = ++nextAnimatedStageId_;
    if (!Os::stdoutSupportsAnimation())
        return stageId;

    animatedStages_.push_back({
        .id     = stageId,
        .lines  = std::move(lines),
        .glyphs = std::move(glyphs),
    });
    return stageId;
}

void Logger::endAnimatedStage(const TaskContext& ctx, const size_t stageId, const std::string_view finalLine)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock lock(*this);
    removeAnimatedStageNoLock(stageId);
    std::cout << finalLine;
    if (finalLine.empty() || finalLine.back() != '\n')
        std::cout << "\n";
    std::cout << std::flush;
}

void Logger::ensureTransientLineSeparated(const TaskContext& ctx, const bool blankLine)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock lock(*this);

    if (transientLineActive_)
        std::cout << "\n";
    if (blankLine && activeStagesWereVisible_)
        std::cout << "\n";
    transientLineActive_ = false;
}

void Logger::print(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock lock(ctx.global().logger());
    std::cout << message;
}

void Logger::printDim(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock lock(ctx.global().logger());
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Dim);
    std::cout << message;
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
}

void Logger::printStdErr(const LogColor color, const std::string_view message, const bool resetColor)
{
    const std::scoped_lock lock(stdErrMutex());
    const bool             useAnsi = Os::stderrSupportsAnsi();

    if (useAnsi)
    {
        switch (color)
        {
            case LogColor::Reset:
                (void) std::fputs("\x1b[0m", stderr);
                break;
            case LogColor::Bold:
                (void) std::fputs("\x1b[1m", stderr);
                break;
            case LogColor::Dim:
                (void) std::fputs("\x1b[2m", stderr);
                break;
            case LogColor::Red:
                (void) std::fputs("\x1b[31m", stderr);
                break;
            case LogColor::Green:
                (void) std::fputs("\x1b[32m", stderr);
                break;
            case LogColor::Yellow:
                (void) std::fputs("\x1b[33m", stderr);
                break;
            case LogColor::Blue:
                (void) std::fputs("\x1b[34m", stderr);
                break;
            case LogColor::Magenta:
                (void) std::fputs("\x1b[35m", stderr);
                break;
            case LogColor::Cyan:
                (void) std::fputs("\x1b[36m", stderr);
                break;
            case LogColor::White:
                (void) std::fputs("\x1b[37m", stderr);
                break;
            case LogColor::BrightRed:
                (void) std::fputs("\x1b[91m", stderr);
                break;
            case LogColor::BrightGreen:
                (void) std::fputs("\x1b[92m", stderr);
                break;
            case LogColor::BrightYellow:
                (void) std::fputs("\x1b[93m", stderr);
                break;
            case LogColor::BrightBlue:
                (void) std::fputs("\x1b[94m", stderr);
                break;
            case LogColor::BrightMagenta:
                (void) std::fputs("\x1b[95m", stderr);
                break;
            case LogColor::BrightCyan:
                (void) std::fputs("\x1b[96m", stderr);
                break;
            case LogColor::Gray:
                (void) std::fputs("\x1b[90m", stderr);
                break;
            default:
                break;
        }
    }

    (void) std::fwrite(message.data(), sizeof(char), message.size(), stderr);
    if (resetColor && useAnsi)
        (void) std::fputs("\x1b[0m", stderr);

    (void) std::fflush(stderr);
}

void Logger::printHeaderDot(const TaskContext& ctx,
                            LogColor           headerColor,
                            std::string_view   header,
                            LogColor           msgColor,
                            std::string_view   message,
                            std::string_view   dot,
                            size_t             messageColumn)
{
    printHeaderDot(ctx, headerColor, header, msgColor, message, LogColor::Gray, dot, messageColumn);
}

void Logger::printHeaderDot(const TaskContext& ctx,
                            LogColor           headerColor,
                            std::string_view   header,
                            LogColor           msgColor,
                            std::string_view   message,
                            LogColor           dotColor,
                            std::string_view   dot,
                            size_t             messageColumn)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock lock(ctx.global().logger());
    ctx.global().logger().ensureTransientLineSeparated(ctx);
    std::cout << LogColorHelper::toAnsi(ctx, headerColor);
    std::cout << header;
    std::cout << LogColorHelper::toAnsi(ctx, dotColor);
    for (size_t i = header.size(); i < messageColumn - 1; ++i)
        std::cout << dot;
    std::cout << " ";
    std::cout << LogColorHelper::toAnsi(ctx, msgColor);
    std::cout << message;
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
    std::cout << "\n";
}

void Logger::printHeaderCentered(const TaskContext& ctx,
                                 LogColor           headerColor,
                                 std::string_view   header,
                                 LogColor           msgColor,
                                 std::string_view   message,
                                 size_t             centerColumn)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock lock(ctx.global().logger());
    ctx.global().logger().ensureTransientLineSeparated(ctx);
    size_t size = header.size();
    while (size < centerColumn)
    {
        std::cout << " ";
        size++;
    }

    std::cout << LogColorHelper::toAnsi(ctx, headerColor);
    std::cout << header;
    std::cout << " ";
    std::cout << LogColorHelper::toAnsi(ctx, msgColor);
    std::cout << message;
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
    std::cout << "\n";
}

void Logger::printAction(const TaskContext& ctx, std::string_view left, std::string_view right)
{
    auto rightColor = LogColor::White;
    if (right.contains("error"))
        rightColor = LogColor::BrightRed;
    else if (right.contains("warning"))
        rightColor = LogColor::Magenta;

    printHeaderCentered(ctx, LogColor::Green, left, rightColor, right);
}

void Logger::animateLoop()
{
    while (!stopAnimator_.load(std::memory_order_acquire))
    {
        std::this_thread::sleep_for(ANIMATION_INTERVAL);
        if (stopAnimator_.load(std::memory_order_acquire))
            return;

        if (!mutexAccess_.try_lock())
            continue;

        if (outputBlockDepth_ == 0 && !animatedStages_.empty())
        {
            for (AnimatedStage& stage : animatedStages_)
                stage.frameIndex = (stage.frameIndex + 1) % stage.lines.size();

            if (renderedStageCount_ == animatedStages_.size())
                updateAnimatedStageGlyphsNoLock();
            else
                renderAnimatedStagesNoLock();
        }

        mutexAccess_.unlock();
    }
}

void Logger::clearAnimatedStagesNoLock(const bool restoreCursor)
{
    if (restoreCursor)
        setCursorVisibleNoLock(true);

    if (renderedStageCount_ == 0)
        return;

    for (size_t i = 0; i < renderedStageCount_; ++i)
        std::cout << "\x1b[1A\r\x1b[2K";

    std::cout << std::flush;
    renderedStageCount_ = 0;
}

void Logger::renderAnimatedStagesNoLock()
{
    if (outputBlockDepth_ != 0 || !Os::stdoutSupportsAnimation())
        return;

    clearAnimatedStagesNoLock(false);
    if (animatedStages_.empty())
    {
        setCursorVisibleNoLock(true);
        return;
    }

    setCursorVisibleNoLock(false);
    for (const AnimatedStage& stage : animatedStages_)
        std::cout << stage.lines[stage.frameIndex] << "\n";

    std::cout << std::flush;
    renderedStageCount_ = animatedStages_.size();
}

void Logger::setCursorVisibleNoLock(const bool visible)
{
    if (!Os::stdoutSupportsAnimation())
    {
        cursorHidden_ = false;
        return;
    }

    if (visible)
    {
        if (!cursorHidden_)
            return;

        std::cout << "\x1b[?25h";
        cursorHidden_ = false;
        return;
    }

    if (cursorHidden_)
        return;

    std::cout << "\x1b[?25l";
    cursorHidden_ = true;
}

void Logger::updateAnimatedStageGlyphsNoLock()
{
    if (outputBlockDepth_ != 0 || renderedStageCount_ == 0 || renderedStageCount_ != animatedStages_.size() || !Os::stdoutSupportsAnimation())
        return;

    setCursorVisibleNoLock(false);
    std::cout << "\x1b[" << renderedStageCount_ << "A";
    for (size_t i = 0; i < animatedStages_.size(); ++i)
    {
        std::cout << "\x1b[3G";
        std::cout << animatedStages_[i].glyphs[animatedStages_[i].frameIndex];
        if (i + 1 < animatedStages_.size())
            std::cout << "\r\x1b[1B";
    }

    std::cout << "\r\x1b[1B" << std::flush;
}

void Logger::removeAnimatedStageNoLock(const size_t stageId)
{
    std::erase_if(animatedStages_, [&](const AnimatedStage& stage) {
        return stage.id == stageId;
    });
}

SWC_END_NAMESPACE();
