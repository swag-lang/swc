#pragma once
#include "Sema/Core/SemaInfo.h"

SWC_BEGIN_NAMESPACE();

struct SwitchPayload
{
    TypeRef exprTypeRef = TypeRef::invalid();
    TypeRef enumTypeRef = TypeRef::invalid();
    bool    isComplete  = false;

    std::unordered_map<ConstantRef, SourceCodeLocation> seen;
};

SWC_END_NAMESPACE();
