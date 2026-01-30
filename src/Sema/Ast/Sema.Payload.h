#pragma once
#include "Sema/Core/SemaInfo.h"

SWC_BEGIN_NAMESPACE();

struct SwitchPayload
{
    TypeRef            exprTypeRef = TypeRef::invalid();
    TypeRef            enumTypeRef = TypeRef::invalid();
    bool               isComplete  = false;
    bool               hasDefault  = false;
    SourceCodeLocation firstDefaultLoc;

    std::unordered_map<ConstantRef, SourceCodeLocation> seen;
};

SWC_END_NAMESPACE();
