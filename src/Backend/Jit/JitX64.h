#pragma once
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Support/Core/Result.h"
#include <functional>

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace Backend
{
    class JitExecutableMemory;

    class JitX64 final
    {
    public:
        static Result compile(TaskContext& ctx, const std::function<void(MicroInstrBuilder&)>& buildFn, JitExecutableMemory& outExecutableMemory);
        static Result compile(TaskContext& ctx, MicroInstrBuilder& builder, JitExecutableMemory& outExecutableMemory);
    };
}

SWC_END_NAMESPACE();
