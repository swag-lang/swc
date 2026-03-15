#include "pch.h"

#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::mutex& stdErrMutex()
    {
        static std::mutex mutex;
        return mutex;
    }
}

void Logger::ensureTransientLineSeparated(const TaskContext& ctx)
{
    if (ctx.cmdLine().silent)
        return;

    if (!transientLineActive_)
        return;

    std::cout << "\n";
    transientLineActive_ = false;
}

void Logger::print(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent)
        return;
    std::cout << message;
}

void Logger::printDim(const TaskContext& ctx, std::string_view message)
{
    if (ctx.cmdLine().silent)
        return;

    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Dim);
    std::cout << message;
    std::cout << LogColorHelper::toAnsi(ctx, LogColor::Reset);
}

void Logger::printStdErr(const LogColor color, const std::string_view message, const bool resetColor)
{
    const std::scoped_lock lock(stdErrMutex());

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

    (void) std::fwrite(message.data(), sizeof(char), message.size(), stderr);
    if (resetColor)
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

    ctx.global().logger().ensureTransientLineSeparated(ctx);
    print(ctx, LogColorHelper::toAnsi(ctx, headerColor));
    print(ctx, header);
    print(ctx, LogColorHelper::toAnsi(ctx, dotColor));
    for (size_t i = header.size(); i < messageColumn - 1; ++i)
        print(ctx, dot);
    print(ctx, " ");
    print(ctx, LogColorHelper::toAnsi(ctx, msgColor));
    print(ctx, message);
    print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Reset));
    print(ctx, "\n");
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

    ctx.global().logger().ensureTransientLineSeparated(ctx);
    size_t size = header.size();
    while (size < centerColumn)
    {
        print(ctx, " ");
        size++;
    }

    print(ctx, LogColorHelper::toAnsi(ctx, headerColor));
    print(ctx, header);
    print(ctx, " ");
    print(ctx, LogColorHelper::toAnsi(ctx, msgColor));
    print(ctx, message);
    print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Reset));
    print(ctx, "\n");
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
