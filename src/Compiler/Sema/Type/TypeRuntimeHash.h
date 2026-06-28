#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;
class TypeInfo;

namespace TypeRuntimeHash
{
    uint32_t compute(const TaskContext& ctx, const TypeInfo& typeInfo);
}

SWC_END_NAMESPACE();
