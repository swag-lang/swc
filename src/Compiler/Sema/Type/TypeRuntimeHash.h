#pragma once
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace TypeRuntimeHash
{
    uint32_t compute(const TaskContext& ctx, const TypeInfo& typeInfo);
}

SWC_END_NAMESPACE();
