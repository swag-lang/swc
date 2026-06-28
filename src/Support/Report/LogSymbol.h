#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

enum class LogSymbol
{
    VerticalLine,
    VerticalLineDot,
    VerticalLineUp,
    DotCenter,
    DotList,
    Check,
    UpToDate,
    Warning,
    Error,
    Cross,
    CommandBuild,
    CommandRun,
    CommandTest,
    CommandFormat,
    CommandSyntax,
    CommandSema,
    CommandUnittest,
    HorizontalLine,
    HorizontalLine2,
    HorizontalLineMidVert,
    HorizontalLine2MidVert,
    DownRight,
    DownLeft,
    UpRight,
    RightDown,
    Underline
};

struct LogSymbolHelper
{
    static Utf8 toString(const TaskContext& ctx, LogSymbol symbol);
};

SWC_END_NAMESPACE();
