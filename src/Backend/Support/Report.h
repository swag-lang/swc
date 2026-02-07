#pragma once

#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

struct Module;

namespace Report
{
inline void internalError(Module*, const char* message)
{
    (void) message;
    SWC_ASSERT(false && "Backend internal error");
}
}

SWC_END_NAMESPACE();
