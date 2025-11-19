#include "pch.h"
#include "TypeInfo.h"

SWC_BEGIN_NAMESPACE()

bool TypeInfo::operator==(const TypeInfo& other) const noexcept
{
    return kind == other.kind;
}

SWC_END_NAMESPACE()
