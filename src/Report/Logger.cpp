#include "pch.h"

#include "LogColor.h"
#include "Logger.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"

SWC_BEGIN_NAMESPACE()

void Logger::print(const CompilerContext& ctx, std::string_view message)
{
    if (ctx.cmdLine()->silent)
        return;
    std::cout << message;
}

void Logger::printEol(const CompilerContext& ctx)
{
    if (ctx.cmdLine()->silent)
        return;
    std::cout << '\n';
}

void Logger::printHeaderDot(const CompilerContext& ctx,
                            LogColor               headerColor,
                            std::string_view       header,
                            LogColor               msgColor,
                            std::string_view       message,
                            std::string_view       dot,
                            size_t                 messageColumn)
{
    if (ctx.cmdLine()->silent)
        return;

    print(ctx, Color::toAnsi(ctx, headerColor));
    print(ctx, header);
    print(ctx, Color::toAnsi(ctx, msgColor));
    for (size_t i = header.size(); i < messageColumn - 1; ++i)
        print(ctx, dot);
    print(ctx, " ");
    print(ctx, message);
    printEol(ctx);
}

SWC_END_NAMESPACE()
