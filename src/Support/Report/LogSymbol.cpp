#include "pch.h"

#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogSymbol.h"

SWC_BEGIN_NAMESPACE();

Utf8 LogSymbolHelper::toString(const TaskContext& ctx, LogSymbol symbol)
{
    const bool ascii = ctx.cmdLine().logAscii;
    switch (symbol)
    {
        case LogSymbol::VerticalLine:
            return ascii ? "|" : "\xE2\x94\x82";
        case LogSymbol::VerticalLineDot:
            return ascii ? "|" : "\xE2\x94\x86";
        case LogSymbol::VerticalLineUp:
            return ascii ? "|" : "\xE2\x95\xB5";
        case LogSymbol::DotCenter:
            return ascii ? "." : "\xC2\xB7";
        case LogSymbol::DotList:
            return ascii ? "*" : "\xE2\x80\xA2";
        case LogSymbol::Cross:
            return ascii ? "X" : "\xE2\x9C\x96";
        case LogSymbol::HorizontalLine:
            return ascii ? "-" : "\xE2\x94\x80";
        case LogSymbol::HorizontalLine2:
            return ascii ? "=" : "\xE2\x95\x90";
        case LogSymbol::HorizontalLineMidVert:
            return ascii ? "-" : "\xE2\x94\xAC";
        case LogSymbol::HorizontalLine2MidVert:
            return ascii ? "=" : "\xE2\x95\xA4";
        case LogSymbol::DownRight:
            return ascii ? "|" : "\xE2\x94\x94";
        case LogSymbol::DownLeft:
            return ascii ? "|" : "\xE2\x94\x98";
        case LogSymbol::UpRight:
            return ascii ? "|" : "\xE2\x94\x8C";
        case LogSymbol::RightDown:
            return ascii ? "|" : "\xE2\x94\x90";
        case LogSymbol::Underline:
            return "^";
    }

    return "?";
}

SWC_END_NAMESPACE();
