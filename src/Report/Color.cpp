#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/Swc.h"
#include "Report/LogColor.h"

std::string_view Color::toAnsi(const CompilerContext& ctx, LogColor c)
{
    if (!ctx.swc().cmdLine().logColor)
        return "";

    using enum LogColor;
    switch (c)
    {
        case Reset:
        default:
            return "\033[0m";
        case Bold:
            return "\033[1m";
        case Dim:
            return "\033[2m";

        case Red:
            return "\033[31m";
        case Green:
            return "\033[32m";
        case Yellow:
            return "\033[33m";
        case Blue:
            return "\033[34m";
        case Magenta:
            return "\033[35m";
        case Cyan:
            return "\033[36m";
        case White:
            return "\033[37m";

        case BrightRed:
            return "\033[91m";
        case BrightGreen:
            return "\033[92m";
        case BrightYellow:
            return "\033[93m";
        case BrightBlue:
            return "\033[94m";
        case BrightMagenta:
            return "\033[95m";
        case BrightCyan:
            return "\033[96m";
    }
}
