#pragma once
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace TypeRuntimeHash
{
    uint32_t compute(const TaskContext& ctx, const TypeInfo& typeInfo);

    // What compute() answers for the aggregate type these parts would build.
    uint32_t computeAggregate(const TaskContext& ctx, TypeInfoKind kind, TypeInfoFlags flags, std::span<const TypeRef> types, std::span<const IdentifierRef> names);
}

SWC_END_NAMESPACE();
