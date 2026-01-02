#pragma once

SWC_BEGIN_NAMESPACE()

enum class Result
{
    Continue,
    SkipChildren,
    Pause,
    Stop
};

#define RESULT_VERIFY(__expr)                                 \
    if (const auto __ret = __expr; __ret != Result::Continue) \
        return __ret;

SWC_END_NAMESPACE()
