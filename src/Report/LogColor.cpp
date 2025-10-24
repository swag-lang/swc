#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

Utf8 LogColorHelper::colorToVts(int r, int g, int b)
{
    return std::format("\x1b[38;2;{};{};{}m", r, g, b);
}

Utf8 LogColorHelper::toAnsi(const Context& ctx, LogColor c)
{
    if (!ctx.cmdLine().logColor)
        return "";

    using enum LogColor;
    switch (c)
    {
        case Reset:
        default:
            return "\x1b[0m";
        case Bold:
            return "\x1b[1m";
        case Dim:
            return "\x1b[2m";

        case Red:
            return "\x1b[31m";
        case Green:
            return "\x1b[32m";
        case Yellow:
            return "\x1b[33m";
        case Blue:
            return "\x1b[34m";
        case Magenta:
            return "\x1b[35m";
        case Cyan:
            return "\x1b[36m";
        case White:
            return "\x1b[37m";

        case BrightBlack:
            return "\x1b[90m";
        case BrightRed:
            return "\x1b[91m";
        case BrightGreen:
            return "\x1b[92m";
        case BrightYellow:
            return "\x1b[93m";
        case BrightBlue:
            return "\x1b[94m";
        case BrightMagenta:
            return "\x1b[95m";
        case BrightCyan:
            return "\x1b[96m";
    }
}

SWC_END_NAMESPACE();
