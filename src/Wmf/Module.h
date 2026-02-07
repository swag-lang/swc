#pragma once
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

struct Module
{
    DataSegment constantSegment;
    DataSegment compilerSegment;
};

SWC_END_NAMESPACE();
