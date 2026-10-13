#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace IntrinsicInitType
{
    TypeRef normalizeTypeRef(TaskContext& ctx, TypeRef typeRef);
}

SWC_END_NAMESPACE();
