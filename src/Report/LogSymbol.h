#pragma once

SWC_BEGIN_NAMESPACE();

class EvalContext;

enum class LogSymbol
{
    VerticalLine,
    VerticalLineDot,
    VerticalLineUp,
    DotCenter,
    DotList,
    Cross,
    HorizontalLine,
    HorizontalLine2,
    HorizontalLineMidVert,
    HorizontalLine2MidVert,
    DownRight,
    DownLeft,
    UpRight,
    RightDown
};

struct LogSymbolHelper
{
    static Utf8 toString(const EvalContext& ctx, LogSymbol symbol);
};

SWC_END_NAMESPACE();
