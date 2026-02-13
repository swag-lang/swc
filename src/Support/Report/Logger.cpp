#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

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

SWC_END_NAMESPACE();
