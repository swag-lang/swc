#pragma once

SWC_BEGIN_NAMESPACE();

enum class Result
{
    Continue,
    SkipChildren,
    Pause,
    Error
};

#define RESULT_VERIFY(__expr)                                     \
    do                                                            \
    {                                                             \
        if (const auto __ret = __expr; __ret != Result::Continue) \
            return __ret;                                         \
    } while (0);

SWC_END_NAMESPACE();
