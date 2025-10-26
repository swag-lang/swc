#pragma once
SWC_BEGIN_NAMESPACE();

namespace Os
{
    void initialize();

    void assertBox(const char* expr, const char* file, int line);
}

SWC_END_NAMESPACE();
