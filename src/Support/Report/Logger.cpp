#include "pch.h"
#include "Support/Report/Logger.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::mutex& stdErrMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    void appendSpaces(Utf8& out, const size_t count)
    {
        out.append(count, ' ');
    }

    void appendColoredText(Utf8& out, const TaskContext& ctx, const LogColor color, const std::string_view text)
    {
        out += LogColorHelper::toAnsi(ctx, color);
        out += text;
        out += LogColorHelper::toAnsi(ctx, LogColor::Reset);
    }

    size_t displayWidth(const std::string_view text)
    {
        return Utf8Helper::countChars(text);
    }

    size_t valueDisplayWidth(const Logger::FieldEntry& entry)
    {
        if (entry.valueParts.empty())
            return displayWidth(entry.value);

        size_t width = 0;
        for (const Logger::FieldValuePart& part : entry.valueParts)
            width += displayWidth(part.text);
        return width;
    }

    size_t entryIndentWidth(const Logger::FieldEntry& entry, const Logger::FieldGroupStyle& style)
    {
        return style.lineIndent + style.indentPerLevel * entry.indentLevel;
    }

    size_t entryLabelWidth(const Logger::FieldEntry& entry, const Logger::FieldGroupStyle& style)
    {
        return entryIndentWidth(entry, style) + displayWidth(entry.label);
    }

    size_t computeLabelColumn(const std::vector<Logger::FieldEntry>& entries, const Logger::FieldGroupStyle& style)
    {
        size_t width = style.minLabelWidth;
        for (const Logger::FieldEntry& entry : entries)
            width = std::max(width, entryLabelWidth(entry, style));

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
        const size_t   indentWidth = entryIndentWidth(entry, style);
        const size_t   labelWidth  = entryLabelWidth(entry, style);

        Utf8 out;
        appendSpaces(out, indentWidth);
        appendColoredText(out, ctx, labelColor, entry.label);
        const size_t padding = labelWidth < labelColumn ? labelColumn - labelWidth + 2 : 2;
        appendSpaces(out, padding);
        appendValue(out, ctx, entry, valueColor);
        out += "\n";
        return out;
    }
}

void Logger::lock()
{
    mutexAccess_.lock();
}

void Logger::unlock()
{
    mutexAccess_.unlock();
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

void Logger::printField(const TaskContext& ctx, const FieldEntry& entry, FieldGroupStyle style)
{
    if (ctx.cmdLine().silent)
        return;

    const ScopedLock              lock(ctx.global().logger());
    const std::vector<FieldEntry> entries = {entry};
    std::cout << formatFieldEntry(ctx, entry, style, computeLabelColumn(entries, style));
}

void Logger::printFieldGroup(const TaskContext& ctx, const std::string_view title, const std::vector<FieldEntry>& entries, FieldGroupStyle style)
{
    if (ctx.cmdLine().silent || entries.empty())
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
    const size_t legacyColumn = messageColumn > 2 ? messageColumn - 2 : 0;
    style.blankLineBefore = false;
    style.minLabelWidth   = std::min(legacyColumn, static_cast<size_t>(28));
    style.maxLabelWidth   = style.minLabelWidth;
    style.maxLineWidth    = std::max(style.maxLineWidth, style.minLabelWidth + 2 + displayWidth(message));
    printField(ctx, entry, style);
}

void Logger::printHeaderCentered(const TaskContext& ctx, LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, size_t centerColumn)
{
    if (ctx.cmdLine().silent)
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
        rightColor = LogColor::BrightRed;
    else if (right.contains("warning"))
        rightColor = LogColor::Magenta;

    printHeaderCentered(ctx, LogColor::Green, left, rightColor, right);
}

SWC_END_NAMESPACE();
