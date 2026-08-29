#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct GenericInstanceKey
{
    TypeRef     typeRef = TypeRef::invalid();
    ConstantRef cstRef  = ConstantRef::invalid();

    bool operator==(const GenericInstanceKey& other) const noexcept
    {
        return typeRef == other.typeRef && cstRef == other.cstRef;
    }
};

SWC_END_NAMESPACE();
