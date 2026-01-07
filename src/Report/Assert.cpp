#include "pch.h"
#include "Os/Os.h"

SWC_BEGIN_NAMESPACE();

void swagAssert(const char* expr, const char* file, int line)
{
    Os::assertBox(expr, file, line);
}

SWC_END_NAMESPACE();
