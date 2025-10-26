#pragma once
SWC_BEGIN_NAMESPACE();

namespace Os
{
    void initialize();

    void     assertBox(const char* expr, const char* file, int line);
    uint64_t timerNow();
    double   timerToSeconds(uint64_t timer);
    Utf8     systemError();
}

SWC_END_NAMESPACE();
