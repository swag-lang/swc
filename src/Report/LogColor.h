#pragma once

SWC_BEGIN_NAMESPACE();

class EvalContext;

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
    std::string_view toAnsi(const EvalContext& ctx, LogColor c);
}

SWC_END_NAMESPACE();
