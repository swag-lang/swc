#include "pch.h"
#include "Support/Report/Logger.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/DiagnosticTypes.h"
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
            // Preserve escape sequences without counting them as visible columns.
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

    Utf8 wrapFieldValue(const std::string_view value, const size_t valueColumn, const size_t maxLineWidth)
    {
        Utf8 continuation = "\n";
        continuation.append(valueColumn, ' ');

        Utf8   out;
        size_t column          = valueColumn;
        size_t lastSpace       = Utf8::npos;
        size_t lastSpaceColumn = 0;
        for (size_t pos = 0; pos < value.size();)
        {
            if (value[pos] == '\x1b' && pos + 1 < value.size() && value[pos + 1] == '[')
            {
                const size_t start = pos;
                pos += 2;
                while (pos < value.size())
                {
                    const unsigned char c = static_cast<unsigned char>(value[pos++]);
                    if (c >= 0x40 && c <= 0x7e)
                        break;
                }
                out.append(value.substr(start, pos - start));
                continue;
            }

            if (value[pos] == '\n')
            {
                out += continuation;
                column    = valueColumn;
                lastSpace = Utf8::npos;
                pos++;
                continue;
            }

            if (column >= maxLineWidth)
            {
                if (value[pos] == ' ')
                {
                    pos++;
                    out += continuation;
                    column = valueColumn;
                }
                else if (lastSpace != Utf8::npos)
                {
                    out.replace(lastSpace, 1, continuation);
                    column = valueColumn + column - lastSpaceColumn - 1;
                }
                else
                {
                    out += continuation;
                    column = valueColumn;
                }
                lastSpace = Utf8::npos;
                continue;
            }

            if (value[pos] == ' ')
            {
                lastSpace       = out.size();
                lastSpaceColumn = column;
            }

            // UTF-8 continuation bytes belong to the same console character.
            const size_t start = pos++;
            while (pos < value.size() && (static_cast<unsigned char>(value[pos]) & 0xc0) == 0x80)
                pos++;
            out.append(value.substr(start, pos - start));
            column++;
        }
        return out;
    }

    Utf8 formatFieldEntry(const TaskContext& ctx, const Logger::FieldEntry& entry, const Logger::FieldGroupStyle& style, const size_t labelColumn)
    {
        (void) ctx;
        (void) style;
        (void) labelColumn;
        Utf8 out;
        if (!entry.label.empty())
        {
            out += entry.label;
            out += ": ";
        }

        if (entry.valueParts.empty())
            out += entry.value;
        else
        {
            for (const Logger::FieldValuePart& part : entry.valueParts)
                out += part.text;
        }
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
    (void) frames;
    return 0;
}

void Logger::updateProgress(const size_t progressId, ProgressFrames frames)
{
    (void) progressId;
    (void) frames;
}

void Logger::endProgress(const size_t progressId, const std::string_view finalLine)
{
    (void) progressId;
    const std::scoped_lock lock(mutexAccess_);
    if (permanentLineOpen_)
    {
        std::cout << "\n";
        permanentLineOpen_ = false;
    }

    std::cout << finalLine;
    if (finalLine.empty() || finalLine.back() != '\n')
        std::cout << "\n";

    std::cout << std::flush;
}

// Abandons an animated progress line without printing anything in its place. Used before the
// console is handed to code the logger cannot coordinate with — a script's own functions, or a
// child process with inherited streams — so the animation does not fight it for the last row.
void Logger::cancelProgress(const size_t progressId)
{
    (void) progressId;
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
    (void) color;
    (void) resetColor;
    const std::scoped_lock lock(stdErrMutex());
    (void) std::fwrite(message.data(), sizeof(char), message.size(), stderr);
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
        std::cout << title;
        std::cout << ":";
        std::cout << "\n";
    }

    const size_t labelColumn = computeLabelColumn(entries, style);
    for (const FieldEntry& entry : entries)
        std::cout << formatFieldEntry(ctx, entry, style, labelColumn);

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
    (void) centerColumn;
    printHeaderDot(ctx, headerColor, header, msgColor, message);
}

void Logger::printAction(const TaskContext& ctx, std::string_view left, std::string_view right)
{
    printHeaderDot(ctx, LogColor::Reset, left, LogColor::Reset, right);
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
    progressRendered_ = false;
}

void Logger::showCursorNoLock()
{
    cursorHidden_ = false;
}

void Logger::renderProgressNoLock()
{
    progressRendered_ = false;
}

SWC_END_NAMESPACE();
