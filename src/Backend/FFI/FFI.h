#pragma once
#include "Backend/JIT/JITExecMemory.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace Backend
{
    class FFI final
    {
    public:
        static Result compileCallU64(TaskContext& ctx, void* targetFn, JITExecMemory& outExecutableMemory);
    };
}

SWC_END_NAMESPACE();
