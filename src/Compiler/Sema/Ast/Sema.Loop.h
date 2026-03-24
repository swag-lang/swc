#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct ForStmtSemaPayload
{
    TypeRef     indexTypeRef = TypeRef::invalid();
    ConstantRef countCstRef  = ConstantRef::invalid();
};

SWC_END_NAMESPACE();
