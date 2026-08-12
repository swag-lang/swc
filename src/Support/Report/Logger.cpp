#include "pch.h"
#include "Support/Report/Logger.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr auto PROGRESS_REFRESH_INTERVAL = std::chrono::milliseconds(120);
    constexpr auto PROGRESS_APPEAR_DELAY     = std::chrono::milliseconds(150);

    Utf8 clipAnsiLine(const std::string_view line, const uint32_t maxColumns)
    {
        if (!maxColumns)
            return Utf8{line};

        Utf8     result;
        uint32_t columns = 0;
        size_t   pos     = 0;
        while (pos < line.size() && columns < maxColumns)
        {
            if (line[pos] == '\x1b' && pos + 1 < line.size() && line[pos + 1] == '[')
            {
                const size_t start = pos;
                pos += 2;
                while (pos < line.size())
                {
                    const unsigned char c = static_cast<unsigned char>(line[pos++]);
                    if (c >= 0x40 && c <= 0x7e)
                        break;
                }
                result.append(line.substr(start, pos - start));
                continue;
            }

            const unsigned char lead = static_cast<unsigned char>(line[pos]);
            size_t              size = 1;
            if ((lead & 0xe0) == 0xc0)
                size = 2;
            else if ((lead & 0xf0) == 0xe0)
                size = 3;
            else if ((lead & 0xf8) == 0xf0)
                size = 4;
            size = std::min(size, line.size() - pos);
            result.append(line.substr(pos, size));
            pos += size;
            columns++;
        }
        return result;
    }

    std::mutex& stdErrMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    void appendColoredText(Utf8& out, const TaskContext& ctx, const LogColor color, const std::string_view text)
    {
        out += LogColorHelper::toAnsi(ctx, color);
        out += text;
        out += LogColorHelper::toAnsi(ctx, LogColor::Reset);
    }

    size_t computeLabelColumn(const std::vector<Logger::FieldEntry>& entries, const Logger::FieldGroupStyle& style)
    {
        size_t width = style.minLabelWidth;
        for (const Logger::FieldEntry& entry : entries)
            width = std::max(width, style.lineIndent + style.indentPerLevel * entry.indentLevel + Utf8Helper::countChars(entry.label));

        return std::min(width, style.maxLabelWidth);
    }

    void appendValue(Utf8& out, const TaskContext& ctx, const Logger::FieldEntry& entry, const LogColor defaultValueColor)
    {
        if (entry.valueParts.empty())
        {
            appendColoredText(out, ctx, defaultValueColor, entry.value);
            return;
        }

        for (const Logger::FieldValuePart& part : entry.valueParts)
        {
            const LogColor partColor = part.color == LogColor::Reset ? defaultValueColor : part.color;
            appendColoredText(out, ctx, partColor, part.text);
        }
    }

    Utf8 formatFieldEntry(const TaskContext& ctx, const Logger::FieldEntry& entry, const Logger::FieldGroupStyle& style, const size_t labelColumn)
    {
        const LogColor labelColor  = entry.labelColor == LogColor::Reset ? style.defaultLabelColor : entry.labelColor;
        const LogColor valueColor  = entry.valueColor == LogColor::Reset ? style.defaultValueColor : entry.valueColor;
        const size_t   indentWidth = style.lineIndent + style.indentPerLevel * entry.indentLevel;
        const size_t   labelWidth  = indentWidth + Utf8Helper::countChars(entry.label);

        Utf8 out;
        out.append(indentWidth, ' ');
        appendColoredText(out, ctx, labelColor, entry.label);
        const size_t padding = labelWidth < labelColumn ? labelColumn - labelWidth + 2 : 2;
        out.append(padding, ' ');
        appendValue(out, ctx, entry, valueColor);
        out += "\n";
        return out;
    }
}

Logger::~Logger()
{
    stopAnimator_.store(true, std::memory_order_release);
    animatorWake_.notify_all();
    if (animator_.joinable())
        animator_.join();

    const std::scoped_lock lock(mutexAccess_);
    clearProgressNoLock();
    showCursorNoLock();
    std::cout << std::flush;
}

void Logger::lock()
{
    mutexAccess_.lock();
    if (outputBlockDepth_++ == 0)
        clearProgressNoLock();
}

void Logger::unlock()
{
    SWC_ASSERT(outputBlockDepth_ != 0);
    outputBlockDepth_--;
    if (outputBlockDepth_ == 0)
        renderProgressNoLock();
    mutexAccess_.unlock();
}

size_t Logger::beginProgress(ProgressFrames frames)
{
    const std::scoped_lock lock(mutexAccess_);
    if (!animator_.joinable())
        animator_ = std::thread([this] { animateLoop(); });
    const size_t progressId = ++nextProgressId_;
    activeProgress_.push_back({.id = progressId, .frames = std::move(frames), .startTick = std::chrono::steady_clock::now()});
    animatorWake_.notify_all();
    return progressId;
}

void Logger::updateProgress(const size_t progressId, ProgressFrames frames)
{
    if (!progressId)
        return;

    const std::scoped_lock lock(mutexAccess_);
    for (ActiveProgress& progress : activeProgress_)
    {
        if (progress.id != progressId)
            continue;
        progress.frames = std::move(frames);
        return;
    }
}

void Logger::endProgress(const size_t progressId, const std::string_view finalLine)
{
    const std::scoped_lock lock(mutexAccess_);
    clearProgressNoLock();
    if (progressId)
    {
        std::erase_if(activeProgress_, [progressId](const ActiveProgress& progress) {
            return progress.id == progressId;
        });
    }

    if (permanentLineOpen_)
    {
        std::cout << "\n";
        permanentLineOpen_ = false;
    }

    std::cout << finalLine;
    if (finalLine.empty() || finalLine.back() != '\n')
        std::cout << "\n";
    if (activeProgress_.empty())
        showCursorNoLock();
    std::cout << std::flush;
}

void Logger::resetStageClaims()
{
    const ScopedLock lock(*this);
    claimedStageKeys_.clear();
}

bool Logger::claimStageOnce(const std::string_view key)
{
    const ScopedLock lock(*this);
    for (const Utf8& existingKey : claimedStageKeys_)
    {
        if (existingKey == key)
            return false;
    }

    claimedStageKeys_.emplace_back(key);
    return true;
}

void Logger::print(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent || ctx.muteOutput())
        return;

    const ScopedLock lock(ctx.global().logger());
    std::cout << message;
    if (!message.empty())
        ctx.global().logger().permanentLineOpen_ = message.back() != '\n';
}

void Logger::printDim(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent || ctx.muteOutput())
        return;

    const ScopedLock lock(ctx.global().logger());
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Dim);
    std::cout << message;
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
    if (!message.empty())
        ctx.global().logger().permanentLineOpen_ = message.back() != '\n';
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

void Logger::printField(const TaskContext& ctx, const FieldEntry& entry, const FieldGroupStyle& style)
{
    if (ctx.cmdLine().silent || ctx.muteOutput())
        return;

    const ScopedLock  lock(ctx.global().logger());
    const std::vector entries = {entry};
    std::cout << formatFieldEntry(ctx, entry, style, computeLabelColumn(entries, style));
}

void Logger::printFieldGroup(const TaskContext& ctx, const std::string_view title, const std::vector<FieldEntry>& entries, const FieldGroupStyle& style)
{
    if (ctx.cmdLine().silent || ctx.muteOutput() || entries.empty())
        return;

    const ScopedLock lock(ctx.global().logger());
    if (!title.empty())
    {
        if (style.blankLineBefore)
            std::cout << "\n";
        std::cout << LogColorHelper::toAnsi(ctx, style.titleColor);
        std::cout << title;
        std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
        std::cout << "\n";
    }

    const size_t labelColumn = computeLabelColumn(entries, style);
    for (const FieldEntry& entry : entries)
        std::cout << formatFieldEntry(ctx, entry, style, labelColumn);

    if (style.blankLineAfter)
        std::cout << "\n";
}

void Logger::printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot, size_t messageColumn)
{
    printHeaderDot(ctx, headerColor, header, msgColor, message, LogColor::Gray, dot, messageColumn);
}

void Logger::printHeaderDot(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, LogColor dotColor, std::string_view dot, size_t messageColumn)
{
    (void) dotColor;
    (void) dot;

    FieldEntry entry;
    entry.label      = Utf8(header);
    entry.value      = Utf8(message);
    entry.labelColor = headerColor;
    entry.valueColor = msgColor;

    FieldGroupStyle style;
    const size_t    legacyColumn = messageColumn > 2 ? messageColumn - 2 : 0;
    style.blankLineBefore        = false;
    style.minLabelWidth          = std::min(legacyColumn, static_cast<size_t>(28));
    style.maxLabelWidth          = style.minLabelWidth;
    style.maxLineWidth           = std::max(style.maxLineWidth, style.minLabelWidth + 2 + Utf8Helper::countChars(message));
    printField(ctx, entry, style);
}

void Logger::printHeaderCentered(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn)
{
    if (ctx.cmdLine().silent || ctx.muteOutput())
        return;

    const ScopedLock lock(ctx.global().logger());
    size_t           size = header.size();
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
        rightColor = LogColorHelper::diagnosticSeverityColor(DiagnosticSeverity::Error);
    else if (right.contains("warning"))
        rightColor = LogColorHelper::diagnosticSeverityColor(DiagnosticSeverity::Warning);

    printHeaderCentered(ctx, LogColor::Green, left, rightColor, right);
}

void Logger::animateLoop()
{
    while (!stopAnimator_.load(std::memory_order_acquire))
    {
        {
            std::unique_lock wakeLock(animatorWakeMutex_);
            animatorWake_.wait_for(wakeLock, PROGRESS_REFRESH_INTERVAL, [this] {
                return stopAnimator_.load(std::memory_order_acquire);
            });
        }

        if (stopAnimator_.load(std::memory_order_acquire))
            return;
        if (!mutexAccess_.try_lock())
            continue;

        if (outputBlockDepth_ == 0 && !activeProgress_.empty())
        {
            ActiveProgress& progress = activeProgress_.back();
            progress.frameIndex      = (progress.frameIndex + 1) % progress.frames.size();
            renderProgressNoLock();
        }

        mutexAccess_.unlock();
    }
}

void Logger::clearProgressNoLock()
{
    if (!progressRendered_)
        return;

    std::cout << "\r\x1b[K";
    progressRendered_ = false;
}

void Logger::showCursorNoLock()
{
    if (!cursorHidden_)
        return;
    Os::setStdoutCursorVisible(true);
    cursorHidden_ = false;
}

void Logger::renderProgressNoLock()
{
    if (outputBlockDepth_ != 0 || permanentLineOpen_ || activeProgress_.empty())
        return;

    ActiveProgress& progress = activeProgress_.back();
    const auto      now      = std::chrono::steady_clock::now();
    if (now - progress.startTick < PROGRESS_APPEAR_DELAY)
        return;

    const uint64_t durationNs = std::chrono::duration_cast<std::chrono::nanoseconds>(now - progress.startTick).count();
    Utf8           line       = progress.frames[progress.frameIndex];
    line += Utf8Helper::toNiceTime(Timer::toSeconds(durationNs));
    line += "\x1b[0m";
    const uint32_t columns = Os::stdoutColumnCount();
    if (columns > 1)
        line = clipAnsiLine(line, columns - 1);

    Utf8 frame;
    if (!cursorHidden_)
    {
        Os::setStdoutCursorVisible(false);
        cursorHidden_ = true;
    }
    frame += "\r";
    frame += line;
    frame += "\x1b[0m\x1b[K";
    std::cout.write(frame.data(), static_cast<std::streamsize>(frame.size()));
    std::cout << std::flush;
    progressRendered_ = true;
}

SWC_END_NAMESPACE();
