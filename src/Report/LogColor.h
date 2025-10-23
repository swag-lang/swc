#pragma once
#include "Main/Global.h"

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
    BrightCyan
};

namespace Color
{
    std::string_view toAnsi(LogColor c);
}
