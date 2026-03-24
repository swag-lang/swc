#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct ForStmtSemaPayload
{
    TypeRef     indexTypeRef  = TypeRef::invalid();
    ConstantRef countCstRef   = ConstantRef::invalid();
    AstNodeRef  lowerBoundRef = AstNodeRef::invalid();
    AstNodeRef  upperBoundRef = AstNodeRef::invalid();
    bool        isRangeLoop   = false;
    bool        inclusive     = false;
};

SWC_END_NAMESPACE();
