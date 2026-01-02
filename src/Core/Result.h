#pragma once

SWC_BEGIN_NAMESPACE()

enum class Result
{
    Continue,
    SkipChildren,
    Pause,
    Stop
};

#define RESULT_VERIFY(__expr)                        \
    if (const ret = __expr; ret != Result::Continue) \
        return ret;

SWC_END_NAMESPACE()
