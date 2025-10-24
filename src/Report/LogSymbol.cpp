#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/EvalContext.h"
#include "Report/LogSymbol.h"

SWC_BEGIN_NAMESPACE();

Utf8 LogSymbolHelper::toString(const EvalContext& ctx, LogSymbol symbol)
{
    const bool ascii = ctx.cmdLine().logAscii;
    switch (symbol)
    {
        case LogSymbol::VerticalLine:
            return ascii ? "|" : "│";
        case LogSymbol::VerticalLineDot:
            return ascii ? "|" : "┆";
        case LogSymbol::VerticalLineUp:
            return ascii ? "|" : "╵";
        case LogSymbol::DotCenter:
            return ascii ? "." : "·";
        case LogSymbol::DotList:
            return ascii ? "*" : "•";
        case LogSymbol::Cross:
            return ascii ? "X" : "✖";
        case LogSymbol::HorizontalLine:
            return ascii ? "-" : "─";
        case LogSymbol::HorizontalLine2:
            return ascii ? "=" : "═";
        case LogSymbol::HorizontalLineMidVert:
            return ascii ? "-" : "┬";
        case LogSymbol::HorizontalLine2MidVert:
            return ascii ? "=" : "╤";
        case LogSymbol::DownRight:
            return ascii ? "|" : "└";
        case LogSymbol::DownLeft:
            return ascii ? "|" : "┘";
        case LogSymbol::UpRight:
            return ascii ? "|" : "┌";
        case LogSymbol::RightDown:
            return ascii ? "|" : "┐";
    }

    return "?";
}

SWC_END_NAMESPACE();
