#pragma once
#include "Sema/Core/SemaInfo.h"

SWC_BEGIN_NAMESPACE();

struct SwitchPayload
{
    std::unordered_map<ConstantRef, AstNodeRef> seen;

    TypeRef    exprTypeRef     = TypeRef::invalid();
    AstNodeRef firstDefaultRef = AstNodeRef::invalid();
    bool       isComplete      = false;
};

SWC_END_NAMESPACE();
