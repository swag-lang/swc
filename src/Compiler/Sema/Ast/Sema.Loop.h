#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct LoopSemaPayload
{
    TypeRef     indexTypeRef  = TypeRef::invalid();
    ConstantRef countCstRef   = ConstantRef::invalid();
    AstNodeRef  lowerBoundRef = AstNodeRef::invalid();
    AstNodeRef  upperBoundRef = AstNodeRef::invalid();
    bool        isRangeLoop   = false;
    bool        inclusive     = false;
    bool        usesLoopIndex = false;
};

SWC_END_NAMESPACE();
