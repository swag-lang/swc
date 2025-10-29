#pragma once

SWC_BEGIN_NAMESPACE()

class Context;

enum class LogColor
{
    Reset,
    Bold,
    Dim,

    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,

    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    BrightBlack,
};

namespace LogColorHelper
{
    Utf8 colorToVts(int r, int g, int b);
    Utf8 toAnsi(const Context& ctx, LogColor c);
}

SWC_END_NAMESPACE()
