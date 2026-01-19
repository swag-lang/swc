#pragma once
#include "Core/StrongRef.h"

SWC_BEGIN_NAMESPACE();
class TaskContext;
class DataSegment;
class TypeInfo;
using TypeRef = StrongRef<TypeInfo>;

namespace TypeGen
{
    uint32_t makeConstantTypeInfo(TaskContext& ctx, DataSegment& storage, TypeRef typeRef);
}

SWC_END_NAMESPACE();
