#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct SliceIndexSemaPayload
{
    AstNodeRef lowerBoundRef = AstNodeRef::invalid();
    AstNodeRef upperBoundRef = AstNodeRef::invalid();
    bool       inclusive     = false;
};

SWC_END_NAMESPACE();
