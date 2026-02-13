#pragma once
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace Backend
{
    class JitExecMemory;

    class Jit final
    {
    public:
        static Result compile(TaskContext& ctx, const std::function<void(MicroInstrBuilder&)>& buildFn, JitExecMemory& outExecutableMemory);
        static Result compile(TaskContext& ctx, MicroInstrBuilder& builder, JitExecMemory& outExecutableMemory);
    };
}

SWC_END_NAMESPACE();
