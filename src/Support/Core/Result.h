#pragma once

SWC_BEGIN_NAMESPACE();

enum class Result
{
    Continue,
    SkipChildren,
    Pause,
    Error
};

#define SWC_RESULT(__expr)                             \
    do                                                 \
    {                                                  \
        const Result __ret = (__expr);                 \
        if (__ret != Result::Continue)                 \
            return __ret;                              \
    } while (0)

SWC_END_NAMESPACE();
